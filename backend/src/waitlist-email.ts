/**
 * The waitlist's confirm email (the owner approved the copy on 2026-10-19). Tables and inline styles only, so it holds
 * up in email clients, with a matching plain-text part. The art and fonts are served from aamirazeez.com.
 */
const ASSETS = "https://aamirazeez.com/after-you/assets/";
const VOID = "#123a3d", CREAM = "#eceddb", INK = "#193d39", INK_SOFT = "#47655e", MINT = "#a6d9c4", MUTED = "#9dbeb4";
const BODY = "'Nunito','Trebuchet MS',Verdana,Arial,sans-serif";
const DISPLAY = "'Fredoka','Nunito','Trebuchet MS',Verdana,Arial,sans-serif";

export const WAITLIST_SENDER = "After You <waitlist@aamirazeez.com>";
export type Email = { subject: string; html: string; text: string };

function escape(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export function confirmEmail(link: string): Email {
  const subject = "Confirm your email for After You on iPhone";
  const href = escape(link);
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
<title>${escape(subject)}</title>
<style>
@font-face{font-family:'Fredoka';src:url('${ASSETS}fredoka-600.woff') format('woff');font-weight:600}
@font-face{font-family:'Nunito';src:url('${ASSETS}nunito-600-800.woff') format('woff');font-weight:600 800}
body{margin:0;padding:0}
@media (max-width:480px){.card{padding:26px 20px 24px!important}.title{font-size:26px!important}}
</style></head>
<body style="margin:0;padding:0;background:${VOID}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">One tap, and I'll email you when After You is on the App Store.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${VOID}">
<tr><td align="center" style="padding:28px 14px 36px">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px">
  <tr><td style="padding:0 6px 16px;font-family:${DISPLAY};font-size:22px;font-weight:600;color:${CREAM}">After You</td></tr>
  <tr><td class="card" style="background:${CREAM};border-radius:24px;padding:30px 32px 28px">
    <img src="${ASSETS}email-spirits.png?v=1" width="240" height="132" alt="Two round spirits, one peach and one mint, smiling with a heart between them." style="display:block;border:0;width:240px;height:132px">
    <h1 class="title" style="margin:18px 0 0;font-family:${DISPLAY};font-size:30px;line-height:1.15;font-weight:600;color:${INK}">One tap to confirm</h1>
    <p style="margin:12px 0 0;font-family:${BODY};font-size:17px;line-height:1.5;color:${INK_SOFT};font-weight:600">You asked to hear when After You is on the App Store. Tap the button so I know this email is yours.</p>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0 4px"><tr>
      <td style="background:${MINT};border-radius:16px"><a href="${href}" style="display:inline-block;padding:15px 26px;font-family:${BODY};font-size:17px;font-weight:800;color:${INK};text-decoration:none;border-radius:16px">Yes, add me</a></td>
    </tr></table>
    <p style="margin:18px 0 0;font-family:${BODY};font-size:14px;line-height:1.5;color:${INK_SOFT};font-weight:600">If you didn't ask for this, ignore this email. I won't add you or write again.</p>
  </td></tr>
  <tr><td style="padding:18px 8px 0;font-family:${BODY};font-size:13px;line-height:1.55;color:${MUTED};font-weight:600">Sent from the After You iPhone list on <a href="https://aamirazeez.com/after-you/link/" style="color:${CREAM}">aamirazeez.com</a>.</td></tr>
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
