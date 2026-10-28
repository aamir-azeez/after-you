/**
 * Vars a deploy sets that wrangler.jsonc does not declare, so `wrangler types` cannot list them.
 * FEATURES is the one switch for server flags (flags.ts featureNames); the deploy runners pin it from live.
 * Merged into the generated Env so code that hands Env to a narrowed type that reads a flag still type-checks.
 */
interface __BaseEnv_Env {
  FEATURES?: string;
}
