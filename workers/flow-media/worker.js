import { createClient } from "@supabase/supabase-js";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID, createHash } from "node:crypto";

const required = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "FLOW_WORKER_ID"];
for (const key of required) if (!process.env[key]) throw new Error("Missing required environment variable: " + key);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const workerId = process.env.FLOW_WORKER_ID;
const bucketExpected = "flow-media-staging";
const maxBytes = Number(process.env.MAX_VIDEO_BYTES || 104857600);
const maxDuration = Number(process.env.MAX_VIDEO_SECONDS || 180);
const pollMs = Number(process.env.POLL_INTERVAL_MS || 5000);
const sleep = ms => new Promise(r => setTimeout(r, ms));

function run(bin, args, timeoutMs = 120000) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "", done = false;
    const timer = setTimeout(() => { child.kill("SIGKILL"); if (!done) { done = true; reject(new Error(bin + " timed out")); } }, timeoutMs);
    child.stdout.on("data", d => { stdout += d.toString(); if (stdout.length > 2_000_000) child.kill("SIGKILL"); });
    child.stderr.on("data", d => { stderr += d.toString(); if (stderr.length > 2_000_000) child.kill("SIGKILL"); });
    child.on("error", e => { clearTimeout(timer); if (!done) { done = true; reject(e); } });
    child.on("close", code => { clearTimeout(timer); if (done) return; done = true; code === 0 ? resolve({ stdout, stderr }) : reject(new Error(bin + " failed: " + stderr.slice(-1200))); });
  });
}
const sha256 = b => createHash("sha256").update(b).digest("hex");
async function setStage(jobId, status) {
  const { error } = await supabase.from("flow_media_processing_jobs").update({ status, updated_at: new Date().toISOString() }).eq("id", jobId).eq("locked_by", workerId);
  if (error) throw error;
}
async function fail(job, code, message, rejected = false) {
  const { error } = await supabase.rpc("flow_fail_media_job_v1", {
    p_job_id: job.job_id, p_worker_id: workerId, p_error_code: code,
    p_safe_message: message, p_rejected: rejected
  });
  if (error) throw error;
}
async function processJob(job) {
  if (job.source_bucket !== bucketExpected || !String(job.source_object_key).startsWith(job.creator_auth_user_id + "/") || String(job.source_object_key).includes("..")) {
    await fail(job, "invalid_source_location", "The uploaded file location is invalid.", true); return;
  }
  const dir = await mkdtemp(join(tmpdir(), "playam-flow-"));
  const input = join(dir, "source.bin"), output = join(dir, "playback.mp4"), thumbnail = join(dir, "thumbnail.jpg");
  try {
    const { data, error } = await supabase.storage.from(bucketExpected).download(job.source_object_key);
    if (error || !data) throw new Error("Could not download source media from private storage");
    const bytes = Buffer.from(await data.arrayBuffer());
    if (bytes.length < 16 || bytes.length > maxBytes) { await fail(job, "file_size_invalid", "Video size is outside the permitted range.", true); return; }
    const digest = sha256(bytes);
    await import("node:fs/promises").then(fs => fs.writeFile(input, bytes, { flag: "wx", mode: 0o600 }));
    await run("clamscan", ["--no-summary", "--infected", input], 90000).catch(async e => {
      if (String(e.message).includes("FOUND")) { await fail(job, "malware_detected", "The uploaded file failed the security scan.", true); throw Object.assign(new Error("Rejected by malware scanner"), { rejected: true }); }
      throw new Error("Malware scanner unavailable or scan failed closed");
    });
    const probe = await run("ffprobe", ["-v","error","-show_entries","format=duration:stream=codec_type,codec_name,width,height","-of","json",input], 30000);
    const meta = JSON.parse(probe.stdout);
    const duration = Number(meta.format?.duration);
    const video = (meta.streams || []).find(s => s.codec_type === "video");
    if (!video || !Number.isFinite(duration) || duration <= 0 || duration > maxDuration || video.width > 3840 || video.height > 2160 || video.width < 160 || video.height < 160) {
      await fail(job, "media_validation_failed", "The video format, dimensions or duration is not supported.", true); return;
    }
    await setStage(job.job_id, "transcoding");
    await run("ffmpeg", ["-nostdin","-v","error","-y","-i",input,"-map","0:v:0","-map","0:a:0?","-t",String(maxDuration),"-vf","scale='min(1920,iw)':-2","-c:v","libx264","-preset","veryfast","-crf","24","-pix_fmt","yuv420p","-c:a","aac","-b:a","128k","-movflags","+faststart","-f","mp4",output], 12*60*1000);
    await setStage(job.job_id, "thumbnailing");
    await run("ffmpeg", ["-nostdin","-v","error","-y","-ss","1","-i",input,"-frames:v","1","-vf","scale='min(720,iw)':-2","-q:v","4",thumbnail], 60000);
    const outBytes = await readFile(output), thumbBytes = await readFile(thumbnail);
    if (!outBytes.length || !thumbBytes.length) throw new Error("Generated media output is empty");
    const prefix = "processed/" + job.creator_auth_user_id + "/" + job.asset_id + "/";
    const playbackKey = prefix + "playback-" + randomUUID() + ".mp4";
    const thumbKey = prefix + "thumbnail-" + randomUUID() + ".jpg";
    const up1 = await supabase.storage.from(bucketExpected).upload(playbackKey, outBytes, { contentType:"video/mp4", upsert:false });
    if (up1.error) throw up1.error;
    const up2 = await supabase.storage.from(bucketExpected).upload(thumbKey, thumbBytes, { contentType:"image/jpeg", upsert:false });
    if (up2.error) { await supabase.storage.from(bucketExpected).remove([playbackKey]); throw up2.error; }
    const done = await supabase.rpc("flow_complete_media_job_v1", {
      p_job_id:job.job_id,p_worker_id:workerId,p_output_bucket:bucketExpected,
      p_output_object_key:playbackKey,p_thumbnail_object_key:thumbKey,
      p_source_sha256:digest,p_output_sha256:sha256(outBytes)
    });
    if (done.error) { await supabase.storage.from(bucketExpected).remove([playbackKey,thumbKey]); throw done.error; }
    console.log(JSON.stringify({ event:"flow_media_processed", job_id:job.job_id, asset_id:job.asset_id }));
  } catch (e) {
    if (e.rejected) return;
    console.error("Flow media job failed", job.job_id, String(e).slice(0,500));
    await fail(job, "processing_failed", "Video processing failed. You can retry the upload.", false);
  } finally {
    await rm(dir,{recursive:true,force:true});
  }
}
async function main() {
  console.log("PLAYAM Flow media worker started", workerId);
  while (true) {
    try {
      const { data: job, error } = await supabase.rpc("flow_claim_media_job_v1",{p_worker_id:workerId});
      if (error) throw error;
      if (job) await processJob(job);
      else await sleep(pollMs);
    } catch (e) {
      console.error("Worker loop error",String(e).slice(0,500));
      await sleep(Math.max(pollMs,10000));
    }
  }
}
main().catch(e=>{console.error(e);process.exit(1);});