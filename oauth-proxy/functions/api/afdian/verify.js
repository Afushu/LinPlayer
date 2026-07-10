// POST /api/afdian/verify — 校验一个爱发电订单号是否真实付款。
//
// 请求体: { "out_trade_no": "20240101xxxx" }
// 返回:   { valid: true, planTitle: "...", amount: "12.00" }  或  { valid: false, reason }
//
// 复用 sponsors.svg.js 同一套环境变量（Cloudflare Pages）：
//   AFDIAN_USER_ID  你的爱发电 user_id
//   AFDIAN_TOKEN    你的爱发电 token（设为 Encrypted）
// 本路由在 /api/ 下，受 _middleware.js 的共享密钥（X-LinPlayer-Key）保护。
//
// ponytail: 只校验「订单存在且已付款」，不做订单号→设备绑定/防转发。
//           开源软锁本就挡君子不挡小人；真泛滥了再加设备白名单（服务端 KV）。

export async function onRequestPost({ request, env }) {
  const userId = env.AFDIAN_USER_ID;
  const token = env.AFDIAN_TOKEN;
  if (!userId || !token) {
    return json({ valid: false, reason: '服务端未配置 AFDIAN_USER_ID / AFDIAN_TOKEN' }, 500);
  }

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ valid: false, reason: '请求体不是合法 JSON' }, 400);
  }
  const orderNo = String((body && body.out_trade_no) || '').trim();
  if (!orderNo) {
    return json({ valid: false, reason: '缺少订单号 out_trade_no' }, 400);
  }

  let order;
  try {
    order = await queryOrder(userId, token, orderNo);
  } catch (e) {
    return json({ valid: false, reason: '查询失败：' + String((e && e.message) || e) }, 502);
  }

  // 爱发电 query-order 只会返回「已付款」的订单；查不到即视为无效订单号。
  if (!order) {
    return json({ valid: false, reason: '订单号不存在或未付款' });
  }
  return json({
    valid: true,
    planTitle: order.plan_title || '',
    amount: order.total_amount || order.show_amount || '0',
    outTradeNo: order.out_trade_no || orderNo,
  });
}

async function queryOrder(userId, token, orderNo) {
  const params = JSON.stringify({ out_trade_no: orderNo });
  const ts = Math.floor(Date.now() / 1000);
  const sign = md5(`${token}params${params}ts${ts}user_id${userId}`);
  const resp = await fetch('https://afdian.com/api/open/query-order', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ user_id: userId, params, ts, sign }),
  });
  const j = await resp.json();
  if (j.ec !== 200) throw new Error(j.em || ('ec=' + j.ec));
  const list = (j.data && j.data.list) || [];
  return list.find((o) => o.out_trade_no === orderNo) || list[0] || null;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// 爱发电签名要求 MD5，Web Crypto 不提供，内联一份紧凑实现（Joseph Myers 版，与 sponsors.svg.js 一致）。
function md5(str) {
  function cmn(q, a, b, x, s, t) { a = add32(add32(a, q), add32(x, t)); return add32((a << s) | (a >>> (32 - s)), b); }
  function ff(a, b, c, d, x, s, t) { return cmn((b & c) | (~b & d), a, b, x, s, t); }
  function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & ~d), a, b, x, s, t); }
  function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | ~d), a, b, x, s, t); }
  function md5cycle(x, k) {
    let a = x[0], b = x[1], c = x[2], d = x[3];
    a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586); c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
    a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426); c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
    a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417); c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
    a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101); c = ff(c, d, a, b, k[14], 17, -1502002290); b = ff(b, c, d, a, k[15], 22, 1236535329);
    a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632); c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
    a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083); c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
    a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690); c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
    a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784); c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
    a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463); c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
    a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353); c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
    a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222); c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
    a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835); c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
    a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415); c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
    a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606); c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
    a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744); c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
    a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379); c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
    x[0] = add32(a, x[0]); x[1] = add32(b, x[1]); x[2] = add32(c, x[2]); x[3] = add32(d, x[3]);
  }
  function md5blk(s) { const b = []; for (let i = 0; i < 64; i += 4) b[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24); return b; }
  function md51(s) {
    const n = s.length, state = [1732584193, -271733879, -1732584194, 271733878]; let i;
    for (i = 64; i <= n; i += 64) md5cycle(state, md5blk(s.substring(i - 64, i)));
    s = s.substring(i - 64);
    const tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (i = 0; i < s.length; i++) tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
    tail[i >> 2] |= 0x80 << ((i % 4) << 3);
    if (i > 55) { md5cycle(state, tail); for (i = 0; i < 16; i++) tail[i] = 0; }
    tail[14] = n * 8;
    md5cycle(state, tail);
    return state;
  }
  const hexChr = '0123456789abcdef'.split('');
  function rhex(x) { let s = ''; for (let j = 0; j < 4; j++) s += hexChr[(x >> (j * 8 + 4)) & 15] + hexChr[(x >> (j * 8)) & 15]; return s; }
  function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
  const bytes = unescape(encodeURIComponent(str)); // UTF-8
  const st = md51(bytes);
  return rhex(st[0]) + rhex(st[1]) + rhex(st[2]) + rhex(st[3]);
}
