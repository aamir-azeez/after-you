/**
 * The waitlist's confirm email (the owner approved the copy on 2026-10-19). Tables and inline styles only, so it holds
 * up in email clients, with a matching plain-text part. The art and fonts are served from aamirazeez.com.
 *
 * Light all the way through, so a client that recolours for dark mode flips the whole email the same way:
 * - Gmail on iOS flips every colour.
 * - Gmail on Android darkens a background only when its brightness (0.299 R + 0.587 G + 0.114 B) is above 205 and
 *   lightens text only below 150; every background here is above 215 and every text colour below 110, the button too,
 *   so nothing is left half flipped (the old mint, at 199, kept its colour while its dark text was lightened).
 * - Apple Mail and Outlook.com honour the color scheme hints and get the game's own dark colours instead.
 */
const ASSETS = "https://aamirazeez.com/after-you/assets/";
const PAGE = "#ffffff", CARD = "#e6eee2", INK = "#193d39", INK_SOFT = "#47655e", BUTTON = "#c2e8d7", FOOT = "#5a746e";
const DARK_PAGE = "#123a3d", DARK_CARD = "#1d4a4b", CREAM = "#eceddb", SOFT = "#cfdccd", MINT = "#a6d9c4", MUTED = "#9dbeb4";
const BODY = "'Nunito','Trebuchet MS',Verdana,Arial,sans-serif";
const DISPLAY = "'Fredoka','Nunito','Trebuchet MS',Verdana,Arial,sans-serif";

/** The From header for the sender address (APP.waitlistFrom in config.ts). */
export function sender(address: string): string { return `After You <${address}>`; }
export type Email = { subject: string; html: string; text: string };

function escape(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** The narrow screen rule, alone, so a rule some client rejects in the other block cannot take it down. */
const LAYOUT_STYLE = `<style>
@media (max-width:480px){.card{padding:26px 20px 24px!important}.title{font-size:26px!important}}
</style>`;

/** Dark mode where the client lets the email choose: Apple Mail (prefers-color-scheme) and Outlook.com ([data-og*]). */
const SCHEME_STYLE = `<style>
@font-face{font-family:'Fredoka';src:url('${ASSETS}fredoka-600.woff') format('woff');font-weight:600}
@font-face{font-family:'Nunito';src:url('${ASSETS}nunito-600-800.woff') format('woff');font-weight:600 800}
:root{color-scheme:light dark;supported-color-schemes:light dark}
body{margin:0;padding:0}
@media (prefers-color-scheme:dark){.bg-page{background-color:${DARK_PAGE}!important}.bg-card{background-color:${DARK_CARD}!important}.bg-button{background-color:${MINT}!important}.t-head{color:${CREAM}!important}.t-body{color:${SOFT}!important}.t-button{color:${INK}!important}.t-foot{color:${MUTED}!important}.t-link{color:${CREAM}!important}}
[data-ogsb] .bg-page{background-color:${DARK_PAGE}!important}
[data-ogsb] .bg-card{background-color:${DARK_CARD}!important}
[data-ogsb] .bg-button{background-color:${MINT}!important}
[data-ogsc] .t-head{color:${CREAM}!important}
[data-ogsc] .t-body{color:${SOFT}!important}
[data-ogsc] .t-button{color:${INK}!important}
[data-ogsc] .t-foot{color:${MUTED}!important}
[data-ogsc] .t-link{color:${CREAM}!important}
</style>`;

export function confirmEmail(link: string): Email {
  const subject = "Confirm your email for After You on iPhone";
  const href = escape(link);
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
<title>${escape(subject)}</title>
${LAYOUT_STYLE}
${SCHEME_STYLE}
</head>
<body class="bg-page" style="margin:0;padding:0;background-color:${PAGE}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">One tap, and I'll email you when After You is on the App Store.</div>
<table role="presentation" class="bg-page" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${PAGE}" style="background-color:${PAGE}">
<tr><td align="center" style="padding:24px 12px 32px">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px">
  <tr><td class="card bg-card" bgcolor="${CARD}" style="background-color:${CARD};border-radius:24px;padding:30px 32px 28px">
    <img src="${ASSETS}email-spirits-v2.png" width="240" height="132" alt="Two round spirits, one peach and one mint, smiling with a heart between them." style="display:block;border:0;width:240px;height:132px">
    <h1 class="title t-head" style="margin:18px 0 0;font-family:${DISPLAY};font-size:30px;line-height:1.15;font-weight:600;color:${INK}">One tap to confirm</h1>
    <p class="t-body" style="margin:12px 0 0;font-family:${BODY};font-size:17px;line-height:1.5;color:${INK_SOFT};font-weight:600">You asked to hear when After You is on the App Store. Tap the button so I know this email is yours.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0 4px"><tr>
      <td class="bg-button" bgcolor="${BUTTON}" style="background-color:${BUTTON};border-radius:16px"><a class="t-button" href="${href}" style="display:inline-block;padding:15px 26px;font-family:${BODY};font-size:17px;font-weight:800;color:${INK};text-decoration:none;border-radius:16px">Yes, add me</a></td>
    </tr></table>
    <p class="t-body" style="margin:18px 0 0;font-family:${BODY};font-size:14px;line-height:1.5;color:${INK_SOFT};font-weight:600">If you didn't ask for this, ignore this email. I won't add you or write again.</p>
  </td></tr>
  <tr><td class="t-foot" style="padding:18px 8px 0;font-family:${BODY};font-size:13px;line-height:1.55;color:${FOOT};font-weight:600">Sent from the After You iPhone list on <a class="t-link" href="https://aamirazeez.com/after-you/link/" style="color:${INK}">aamirazeez.com</a>.</td></tr>
  </table>
</td></tr></table>
</body></html>
`;
  const text = `One tap to confirm

You asked to hear when After You is on the App Store. Open this link so I know this email is yours:
${link}

If you didn't ask for this, ignore this email. I won't add you or write again.

After You, aamirazeez.com
`;
  return { subject, html, text };
}
