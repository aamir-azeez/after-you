/**
 * Tests still switch flags through their dedicated vars, which flagOn reads beside FEATURES, but wrangler.jsonc no
 * longer declares them, so `wrangler types` leaves them out of Env. This puts every flag var back on Env, as an
 * optional string, for the tests only.
 */
type TestFlagVars = { [V in import("../src/flags").FlagVar]?: string };
interface __BaseEnv_Env extends TestFlagVars {}
