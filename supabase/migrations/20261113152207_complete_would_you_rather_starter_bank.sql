-- Exported from PLAYAM Staging migration history (20261113152207).
-- Apply only to the matching Staging project after reviewing the migration.

insert into public.questions(text,category,active,level,game_key,difficulty_key,question_type,option_a,option_b)
select v.question_text,v.category,true,1,'would-you-rather','starter','choice',v.option_a,v.option_b
from (values
('Would you rather be able to pause time or rewind it once a day?','Big Decisions','Pause time','Rewind time'),
('Would you rather have a library of every book or a cinema showing every film?','Entertainment','Every book','Every film'),
('Would you rather always know the right thing to say or always know the right time to say it?','Social Skills','Right words','Right timing'),
('Would you rather explore outer space or the deepest ocean?','Adventure','Outer space','Deep ocean')
) v(question_text,category,option_a,option_b)
where not exists(select 1 from public.questions q where q.game_key='would-you-rather' and q.difficulty_key='starter' and q.text=v.question_text);

