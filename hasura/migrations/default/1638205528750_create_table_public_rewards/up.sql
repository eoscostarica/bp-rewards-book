CREATE TABLE "public"."rewards" ("id" uuid NOT NULL DEFAULT gen_random_uuid(), "trxid" text NOT NULL, "account" text NOT NULL, "quantity" text NOT NULL, "usd_quantity" numeric NOT NULL, "rate" numeric NOT NULL, "claimned_at" timestamptz NOT NULL, "created_at" timestamptz NOT NULL DEFAULT now(), "updated_at" timestamptz NOT NULL DEFAULT now(), PRIMARY KEY ("id") );
CREATE OR REPLACE FUNCTION "public"."set_current_timestamp_updated_at"()
RETURNS TRIGGER AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "set_public_rewards_updated_at"
BEFORE UPDATE ON "public"."rewards"
FOR EACH ROW
EXECUTE PROCEDURE "public"."set_current_timestamp_updated_at"();
COMMENT ON TRIGGER "set_public_rewards_updated_at" ON "public"."rewards" 
IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE EXTENSION IF NOT EXISTS pgcrypto;
