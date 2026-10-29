/**
 * The one var a deploy sets, which wrangler.jsonc never declares (it holds the owner's friend aliases, which must not
 * reach Git), so `wrangler types` cannot list it. config.ts parses it; the deploy runners pin it from live.
 */
interface __BaseEnv_Env {
  CONFIG?: string;
}
