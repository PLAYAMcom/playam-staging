-- PLAYAM global market foundation.
-- This file documents migrations already applied to the isolated Staging project.
-- Do not replay blindly against a project with these objects already present.

CREATE TABLE IF NOT EXISTS private.playam_market_countries (
  country_code text PRIMARY KEY CHECK (country_code ~ '^[A-Z]{2}$'),
  country_name text NOT NULL,
  rollout_status text NOT NULL DEFAULT 'planned'
    CHECK (rollout_status IN ('planned','internal','testing','live','paused')),
  default_currency_code text NOT NULL CHECK (default_currency_code ~ '^[A-Z]{3}$'),
  default_locale text NOT NULL,
  default_timezone text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS private.playam_market_currencies (
  country_code text NOT NULL REFERENCES private.playam_market_countries(country_code) ON DELETE RESTRICT,
  currency_code text NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  minor_unit_digits smallint NOT NULL CHECK (minor_unit_digits BETWEEN 0 AND 4),
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (country_code, currency_code)
);
CREATE UNIQUE INDEX IF NOT EXISTS playam_market_one_default_currency_per_country
  ON private.playam_market_currencies(country_code) WHERE is_default;

CREATE TABLE IF NOT EXISTS private.playam_market_payment_methods (
  country_code text NOT NULL REFERENCES private.playam_market_countries(country_code) ON DELETE RESTRICT,
  provider_code text NOT NULL CHECK (provider_code IN ('paystack','opay','flutterwave')),
  currency_code text NOT NULL,
  availability_status text NOT NULL DEFAULT 'not_verified'
    CHECK (availability_status IN ('not_verified','under_review','approved','enabled','suspended')),
  notes text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (country_code, provider_code, currency_code),
  FOREIGN KEY (country_code, currency_code)
    REFERENCES private.playam_market_currencies(country_code, currency_code) ON DELETE RESTRICT
);

ALTER TABLE private.playam_market_countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.playam_market_currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.playam_market_payment_methods ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON private.playam_market_countries, private.playam_market_currencies,
  private.playam_market_payment_methods FROM anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON private.playam_market_countries,
  private.playam_market_currencies, private.playam_market_payment_methods TO service_role;

DROP POLICY IF EXISTS service_role_manage_market_countries ON private.playam_market_countries;
CREATE POLICY service_role_manage_market_countries ON private.playam_market_countries
  FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS service_role_manage_market_currencies ON private.playam_market_currencies;
CREATE POLICY service_role_manage_market_currencies ON private.playam_market_currencies
  FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS service_role_manage_market_payment_methods ON private.playam_market_payment_methods;
CREATE POLICY service_role_manage_market_payment_methods ON private.playam_market_payment_methods
  FOR ALL TO service_role USING (true) WITH CHECK (true);

INSERT INTO private.playam_market_countries
  (country_code,country_name,rollout_status,default_currency_code,default_locale,default_timezone)
VALUES
  ('NG','Nigeria','internal','NGN','en-NG','Africa/Lagos'),
  ('GB','United Kingdom','planned','GBP','en-GB','Europe/London'),
  ('GH','Ghana','planned','GHS','en-GH','Africa/Accra'),
  ('US','United States','planned','USD','en-US','America/New_York')
ON CONFLICT (country_code) DO NOTHING;

INSERT INTO private.playam_market_currencies
  (country_code,currency_code,minor_unit_digits,is_default)
VALUES
  ('NG','NGN',2,true),('GB','GBP',2,true),('GH','GHS',2,true),('US','USD',2,true)
ON CONFLICT (country_code,currency_code) DO NOTHING;

INSERT INTO private.playam_market_payment_methods
  (country_code,provider_code,currency_code,availability_status,notes)
VALUES
  ('NG','paystack','NGN','not_verified','Primary provider candidate; activation requires verified account configuration and end-to-end tests.'),
  ('NG','opay','NGN','not_verified','Only as a Paystack checkout option where enabled and approved.'),
  ('GB','paystack','GBP','not_verified','International market; provider eligibility and currency support must be confirmed in writing.'),
  ('GH','paystack','GHS','not_verified','Market and provider eligibility not yet verified.'),
  ('US','paystack','USD','not_verified','Market and provider eligibility not yet verified.')
ON CONFLICT (country_code,provider_code,currency_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.playam_user_market_preferences (
  auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  country_code text NOT NULL REFERENCES private.playam_market_countries(country_code) ON DELETE RESTRICT,
  preferred_currency_code text NOT NULL,
  locale text NOT NULL,
  timezone text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT playam_user_market_currency_fk
    FOREIGN KEY (country_code,preferred_currency_code)
    REFERENCES private.playam_market_currencies(country_code,currency_code) ON DELETE RESTRICT
);

ALTER TABLE public.playam_user_market_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS playam_users_read_own_market_preference ON public.playam_user_market_preferences;
CREATE POLICY playam_users_read_own_market_preference ON public.playam_user_market_preferences
  FOR SELECT TO authenticated USING (auth.uid()=auth_user_id);
DROP POLICY IF EXISTS playam_users_insert_own_market_preference ON public.playam_user_market_preferences;
CREATE POLICY playam_users_insert_own_market_preference ON public.playam_user_market_preferences
  FOR INSERT TO authenticated WITH CHECK (auth.uid()=auth_user_id);
DROP POLICY IF EXISTS playam_users_update_own_market_preference ON public.playam_user_market_preferences;
CREATE POLICY playam_users_update_own_market_preference ON public.playam_user_market_preferences
  FOR UPDATE TO authenticated USING (auth.uid()=auth_user_id) WITH CHECK (auth.uid()=auth_user_id);

REVOKE ALL ON public.playam_user_market_preferences FROM anon;
GRANT SELECT,INSERT,UPDATE ON public.playam_user_market_preferences TO authenticated;
GRANT ALL ON public.playam_user_market_preferences TO service_role;

CREATE OR REPLACE FUNCTION public.playam_get_available_markets_v1()
RETURNS TABLE(country_code text,country_name text,currency_code text,locale text,timezone text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  RETURN QUERY
  SELECT c.country_code,c.country_name,c.default_currency_code,c.default_locale,c.default_timezone
  FROM private.playam_market_countries c
  JOIN private.playam_market_currencies m
    ON m.country_code=c.country_code AND m.currency_code=c.default_currency_code AND m.is_default
  WHERE c.rollout_status IN ('internal','testing','live')
  ORDER BY CASE c.country_code WHEN 'NG' THEN 0 ELSE 1 END,c.country_name;
END;
$function$;
REVOKE ALL ON FUNCTION public.playam_get_available_markets_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.playam_get_available_markets_v1() TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.playam_set_user_market_preference_v1(
  p_country_code text,p_currency_code text,p_locale text DEFAULT NULL,p_timezone text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_country text:=upper(btrim(coalesce(p_country_code,'')));
  v_currency text:=upper(btrim(coalesce(p_currency_code,'')));
  v_locale text;
  v_timezone text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT c.default_locale,c.default_timezone INTO v_locale,v_timezone
  FROM private.playam_market_countries c
  JOIN private.playam_market_currencies m
    ON m.country_code=c.country_code AND m.currency_code=v_currency AND m.is_default
  WHERE c.country_code=v_country AND c.rollout_status IN ('internal','testing','live');
  IF NOT FOUND THEN RAISE EXCEPTION 'This market is not currently available'; END IF;
  v_locale:=coalesce(nullif(btrim(p_locale),''),v_locale);
  v_timezone:=coalesce(nullif(btrim(p_timezone),''),v_timezone);
  IF length(v_locale)>35 OR length(v_timezone)>64 THEN RAISE EXCEPTION 'Invalid locale or timezone'; END IF;
  INSERT INTO public.playam_user_market_preferences
    (auth_user_id,country_code,preferred_currency_code,locale,timezone,updated_at)
  VALUES (v_uid,v_country,v_currency,v_locale,v_timezone,now())
  ON CONFLICT (auth_user_id) DO UPDATE SET
    country_code=excluded.country_code,
    preferred_currency_code=excluded.preferred_currency_code,
    locale=excluded.locale,timezone=excluded.timezone,updated_at=now();
END;
$function$;
REVOKE ALL ON FUNCTION public.playam_set_user_market_preference_v1(text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.playam_set_user_market_preference_v1(text,text,text,text) TO authenticated,service_role;
