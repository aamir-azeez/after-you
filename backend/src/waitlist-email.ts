/**
 * The waitlist's confirm email (the owner approved the copy on 2026-10-19). Tables and inline styles only, so it holds
 * up in email clients, with a matching plain-text part. The art and fonts are served from aamirazeez.com.
 *
 * Dark mode keeps the light look:
 * - Apple Mail and Outlook.com: the color scheme hints, a prefers-color-scheme block and [data-ogsc]/[data-ogsb] rules.
 * - Gmail's apps recolour everything (iOS flips every colour, Android darkens light backgrounds and lightens dark text)
 *   but never a background image, so the second style block, under Gmail's own `u + .body`, pins each surface with a one
 *   colour gradient and draws each text run through blend layers whose result is the same with or without the recolour:
 *   white text on black differenced (Colton Eakins' pair), turned into a mask on white, then tinted by a gradient.
 * - Where Gmail drops the style block (accounts that are not Google's) nothing is pinned and the plain flip still reads;
 *   the button is then dark with light text, since Android would wash out dark text on mint.
 */
const ASSETS = "https://aamirazeez.com/after-you/assets/";
const PAGE = "#123a3d", CREAM = "#eceddb", INK = "#193d39", INK_SOFT = "#47655e", MINT = "#a6d9c4", MUTED = "#9dbeb4";
const BUTTON_PLAIN = "#276457";
const BODY = "'Nunito','Trebuchet MS',Verdana,Arial,sans-serif";
const DISPLAY = "'Fredoka','Nunito','Trebuchet MS',Verdana,Arial,sans-serif";

/** The From header for a sender address (WAITLIST_FROM); the address is checked before it gets here. */
export function sender(address: string): string { return `After You <${address}>`; }
export type Email = { subject: string; html: string; text: string };

function escape(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

const pin = (color: string) => `background-image:linear-gradient(${color},${color})!important`;

/** For every client that reads a style block: the mint button, and the same colours again for Apple Mail and Outlook.com in dark mode. */
const LOOK_STYLE = `<style>
@font-face{font-family:'Fredoka';src:url('${ASSETS}fredoka-600.woff') format('woff');font-weight:600}
@font-face{font-family:'Nunito';src:url('${ASSETS}nunito-600-800.woff') format('woff');font-weight:600 800}
:root{color-scheme:light dark;supported-color-schemes:light dark}
body{margin:0;padding:0}
.bg-button{background-color:${MINT}!important}
.t-button{color:${INK}!important}
@media (prefers-color-scheme:dark){.bg-page{background-color:${PAGE}!important}.bg-card{background-color:${CREAM}!important}.bg-button{background-color:${MINT}!important}.t-ink,.t-button{color:${INK}!important}.t-soft{color:${INK_SOFT}!important}.t-muted{color:${MUTED}!important}.t-cream{color:${CREAM}!important}}
[data-ogsb] .bg-page{background-color:${PAGE}!important}
[data-ogsb] .bg-card{background-color:${CREAM}!important}
[data-ogsb] .bg-button{background-color:${MINT}!important}
[data-ogsc] .t-ink,[data-ogsc] .t-button{color:${INK}!important}
[data-ogsc] .t-soft{color:${INK_SOFT}!important}
[data-ogsc] .t-muted{color:${MUTED}!important}
[data-ogsc] .t-cream{color:${CREAM}!important}
</style>`;

/** Gmail only (its `<u></u>` before the body). Kept in its own block so a rule Gmail rejects elsewhere cannot take it down. */
const GMAIL_STYLE = `<style>
@media (max-width:480px){.card{padding:26px 20px 24px!important}.title{font-size:26px!important}}
u + .body .bg-page{${pin(PAGE)}}
u + .body .bg-card{${pin(CREAM)}}
u + .body .bg-button{${pin(MINT)}}
u + .body .lk-ink{${pin(INK)};mix-blend-mode:multiply}
u + .body .lk-soft{${pin(INK_SOFT)};mix-blend-mode:multiply}
u + .body .lk-white{${pin("#ffffff")};mix-blend-mode:screen}
u + .body .lk-flip{background-color:#000000;mix-blend-mode:exclusion}
u + .body .lk-muted{${pin(MUTED)};mix-blend-mode:screen}
u + .body .lk-cream{${pin(CREAM)};mix-blend-mode:screen}
u + .body .lk-mask{background-color:#000000;mix-blend-mode:multiply}
u + .body .lk-text{background-color:#000000;color:#ffffff!important;mix-blend-mode:difference}
</style>`;

/** Dark text that Gmail's dark mode cannot recolour: shows `tint` on a light pinned surface. */
function darkText(tint: "ink" | "soft", inner: string): string {
  return `<span class="lk-${tint}"><span class="lk-white"><span class="lk-flip"><span class="lk-text">${inner}</span></span></span></span>`;
}

/** Light text that Gmail's dark mode cannot recolour: shows `tint` on a dark pinned surface. */
function lightText(tint: "muted" | "cream", inner: string): string {
  return `<span class="lk-${tint}"><span class="lk-mask"><span class="lk-text">${inner}</span></span></span>`;
}

export function confirmEmail(link: string): Email {
  const subject = "Confirm your email for After You on iPhone";
  const href = escape(link);
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
<title>${escape(subject)}</title>
${LOOK_STYLE}
${GMAIL_STYLE}
</head>
<body class="body" style="margin:0;padding:0;background-color:${PAGE}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">One tap, and I'll email you when After You is on the App Store.</div>
<table role="presentation" class="bg-page" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${PAGE}" style="background-color:${PAGE}">
<tr><td align="center" style="padding:28px 14px 36px">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px">
  <tr><td class="card bg-card" bgcolor="${CREAM}" style="background-color:${CREAM};border-radius:24px;padding:30px 32px 28px">
    <img src="${ASSETS}email-spirits-v2.png" width="240" height="132" alt="Two round spirits, one peach and one mint, smiling with a heart between them." style="display:block;border:0;width:240px;height:132px">
    <h1 class="title t-ink" style="margin:18px 0 0;font-family:${DISPLAY};font-size:30px;line-height:1.15;font-weight:600;color:${INK}">${darkText("ink", "One tap to confirm")}</h1>
    <p class="t-soft" style="margin:12px 0 0;font-family:${BODY};font-size:17px;line-height:1.5;color:${INK_SOFT};font-weight:600">${darkText("soft", "You asked to hear when After You is on the App Store. Tap the button so I know this email is yours.")}</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0 4px"><tr>
      <td class="bg-button" bgcolor="${BUTTON_PLAIN}" style="background-color:${BUTTON_PLAIN};border-radius:16px"><a class="t-button" href="${href}" style="display:inline-block;padding:15px 26px;font-family:${BODY};font-size:17px;font-weight:800;color:${CREAM};text-decoration:none;border-radius:16px">${darkText("ink", "Yes, add me")}</a></td>
    </tr></table>
    <p class="t-soft" style="margin:18px 0 0;font-family:${BODY};font-size:14px;line-height:1.5;color:${INK_SOFT};font-weight:600">${darkText("soft", "If you didn't ask for this, ignore this email. I won't add you or write again.")}</p>
  </td></tr>
  <tr><td class="t-muted" style="padding:18px 8px 0;font-family:${BODY};font-size:13px;line-height:1.55;color:${MUTED};font-weight:600">${lightText("muted", "Sent from the After You iPhone list on ")}<a class="t-cream" href="https://aamirazeez.com/after-you/link/" style="color:${CREAM};text-decoration:none">${lightText("cream", `<span style="text-decoration:underline">aamirazeez.com</span>`)}</a>${lightText("muted", ".")}</td></tr>
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
