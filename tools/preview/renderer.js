// Approximates Roblox's 2D GUI layout well enough to eyeball the plugin UI in
// a browser: UDim2 sizing/positioning, AnchorPoint, UIPadding, UIListLayout,
// AutomaticSize, UICorner, UIStroke, UIGradient, rotation, clipping and text.
// Text uses a system sans-serif instead of Builder Sans.

const FONT = '"Liberation Sans", "DejaVu Sans", Arial, sans-serif';
const WEIGHTS = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Heavy: 900 };
const GUI = new Set(["Frame", "TextLabel", "TextButton", "ScrollingFrame", "ImageLabel", "ImageButton", "TextBox"]);
const TEXT = new Set(["TextLabel", "TextButton", "TextBox"]);

const canvas = document.createElement("canvas");
const ctx = canvas.getContext("2d");

const child = (node, cls) => node.children.find((c) => c.class === cls);
const guiChildren = (node) => node.children.filter((c) => GUI.has(c.class));
const visible = (node) => node.props.Visible !== false;
const udim2 = (v) => v || { xs: 0, xo: 0, ys: 0, yo: 0 };
const plain = (text) => String(text || "").replace(/<[^>]+>/g, "");

function fontFor(node) {
  const weight = WEIGHTS[node.props.FontFace] || 400;
  return `${weight} ${node.props.TextSize}px ${FONT}`;
}

function textWidth(node) {
  ctx.font = fontFor(node);
  return ctx.measureText(plain(node.props.Text)).width;
}

function padding(node, size) {
  const p = child(node, "UIPadding");
  if (!p) return { l: 0, r: 0, t: 0, b: 0 };
  const u = (v, total) => (v ? v.s * total + v.o : 0);
  return {
    l: u(p.props.PaddingLeft, size.w),
    r: u(p.props.PaddingRight, size.w),
    t: u(p.props.PaddingTop, size.h),
    b: u(p.props.PaddingBottom, size.h),
  };
}

function sorted(nodes) {
  return nodes
    .map((n, i) => [n, i])
    .sort((a, b) => (a[0].props.LayoutOrder || 0) - (b[0].props.LayoutOrder || 0) || a[1] - b[1])
    .map((p) => p[0]);
}

function resolveSize(node, parent) {
  const s = udim2(node.props.Size);
  let w = parent.w * s.xs + s.xo;
  let h = parent.h * s.ys + s.yo;
  const auto = node.props.AutomaticSize || "None";
  if (auto !== "None") {
    const content = contentExtent(node, { w, h });
    if (auto.includes("X")) w = Math.max(w, content.w);
    if (auto.includes("Y")) h = Math.max(h, content.h);
  }
  return { w, h };
}

function contentExtent(node, size) {
  const pad = padding(node, size);
  let w = 0;
  let h = 0;
  if (TEXT.has(node.class) && node.props.Text) {
    w = textWidth(node) + pad.l + pad.r;
    h = node.props.TextSize + pad.t + pad.b;
  }
  const inner = { w: size.w - pad.l - pad.r, h: size.h - pad.t - pad.b };
  const kids = guiChildren(node).filter(visible);
  const list = child(node, "UIListLayout");
  if (list) {
    const gap = list.props.Padding ? list.props.Padding.o : 0;
    const horizontal = list.props.FillDirection === "Horizontal";
    let main = 0;
    let cross = 0;
    kids.forEach((kid, i) => {
      const k = resolveSize(kid, inner);
      main += (horizontal ? k.w : k.h) + (i > 0 ? gap : 0);
      cross = Math.max(cross, horizontal ? k.h : k.w);
    });
    w = Math.max(w, (horizontal ? main : cross) + pad.l + pad.r);
    h = Math.max(h, (horizontal ? cross : main) + pad.t + pad.b);
  } else {
    for (const kid of kids) {
      const k = resolveSize(kid, inner);
      const p = udim2(kid.props.Position);
      const a = kid.props.AnchorPoint || { x: 0, y: 0 };
      w = Math.max(w, p.xo - a.x * k.w + k.w + pad.l + pad.r);
      h = Math.max(h, p.yo - a.y * k.h + k.h + pad.t + pad.b);
    }
  }
  return { w, h };
}

function layoutChildren(node) {
  const r = node.rect;
  const pad = padding(node, r);
  const scroll = node.class === "ScrollingFrame" && node.props.CanvasPosition ? node.props.CanvasPosition : { x: 0, y: 0 };
  const inner = { x: r.x + pad.l - scroll.x, y: r.y + pad.t - scroll.y, w: r.w - pad.l - pad.r, h: r.h - pad.t - pad.b };
  const kids = guiChildren(node);
  const list = child(node, "UIListLayout");
  if (list) {
    const gap = list.props.Padding ? list.props.Padding.o : 0;
    const horizontal = list.props.FillDirection === "Horizontal";
    let cursor = 0;
    for (const kid of sorted(kids)) {
      const size = resolveSize(kid, inner);
      kid.rect = horizontal
        ? { x: inner.x + cursor, y: inner.y, w: size.w, h: size.h }
        : { x: inner.x, y: inner.y + cursor, w: size.w, h: size.h };
      if (visible(kid)) cursor += (horizontal ? size.w : size.h) + gap;
      layoutChildren(kid);
    }
  } else {
    for (const kid of kids) {
      const size = resolveSize(kid, inner);
      const p = udim2(kid.props.Position);
      const a = kid.props.AnchorPoint || { x: 0, y: 0 };
      kid.rect = {
        x: inner.x + inner.w * p.xs + p.xo - a.x * size.w,
        y: inner.y + inner.h * p.ys + p.yo - a.y * size.h,
        w: size.w,
        h: size.h,
      };
      layoutChildren(kid);
    }
  }
}

const rgba = (c, transparency) =>
  `rgba(${Math.round(c[0] * 255)}, ${Math.round(c[1] * 255)}, ${Math.round(c[2] * 255)}, ${Math.max(0, 1 - transparency)})`;

function sampleNumberSequence(seq, t) {
  if (!seq) return 0;
  for (let i = 0; i < seq.length - 1; i++) {
    const a = seq[i];
    const b = seq[i + 1];
    if (t >= a.t && t <= b.t) return a.v + ((b.v - a.v) * (t - a.t)) / (b.t - a.t || 1);
  }
  return seq[seq.length - 1].v;
}

function sampleColorSequence(seq, t) {
  for (let i = 0; i < seq.length - 1; i++) {
    const a = seq[i];
    const b = seq[i + 1];
    if (t >= a.t && t <= b.t) {
      const f = (t - a.t) / (b.t - a.t || 1);
      return a.c.map((v, j) => v + (b.c[j] - v) * f);
    }
  }
  return seq[seq.length - 1].c;
}

function background(node) {
  const props = node.props;
  const base = props.BackgroundTransparency;
  if (base >= 1) return null;
  const gradient = child(node, "UIGradient");
  const color = props.BackgroundColor3;
  if (!gradient || gradient.props.Enabled === false) return rgba(color, base);
  const stops = [];
  for (let i = 0; i <= 10; i++) {
    const t = i / 10;
    const g = gradient.props.Color ? sampleColorSequence(gradient.props.Color, t) : [1, 1, 1];
    const transparency = sampleNumberSequence(gradient.props.Transparency, t);
    const c = color.map((v, j) => v * g[j]);
    const alpha = 1 - (1 - base) * (1 - transparency);
    stops.push(`${rgba(c, alpha)} ${t * 100}%`);
  }
  return `linear-gradient(${90 + (gradient.props.Rotation || 0)}deg, ${stops.join(", ")})`;
}

function cornerRadius(node) {
  const corner = child(node, "UICorner");
  if (!corner) return 0;
  const r = corner.props.CornerRadius || { s: 0, o: 8 };
  const min = Math.min(node.rect.w, node.rect.h);
  return Math.min(r.s * min + r.o, min / 2);
}

function richText(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/<font color="([^"]+)">/g, '<span style="color:$1">')
    .replace(/<\/font>/g, "</span>");
}

function render(node, parentEl, parentRect) {
  if (!visible(node) || !node.rect) return;
  const r = node.rect;
  const props = node.props;
  const el = document.createElement("div");
  el.style.cssText = `position:absolute;left:${r.x - parentRect.x}px;top:${r.y - parentRect.y}px;width:${r.w}px;height:${r.h}px;`;
  if (props.Rotation) el.style.transform = `rotate(${props.Rotation}deg)`;
  const scale = child(node, "UIScale");
  if (scale && scale.props.Scale !== undefined && scale.props.Scale !== 1) {
    el.style.transform = (el.style.transform || "") + ` scale(${scale.props.Scale})`;
  }

  const radius = cornerRadius(node);
  const bg = background(node);
  const stroke = child(node, "UIStroke");
  const layer = document.createElement("div");
  layer.style.cssText = `position:absolute;inset:0;border-radius:${radius}px;`;
  if (bg) layer.style.background = bg;
  if (stroke && stroke.props.Enabled !== false && (stroke.props.Transparency ?? 0) < 1) {
    const color = stroke.props.Color || [0, 0, 0];
    layer.style.boxShadow = `0 0 0 ${stroke.props.Thickness ?? 1}px ${rgba(color, stroke.props.Transparency ?? 0)}`;
  }
  el.appendChild(layer);

  if (TEXT.has(node.class) && props.Text) {
    const pad = padding(node, r);
    const text = document.createElement("div");
    const x = props.TextXAlignment || "Center";
    const y = props.TextYAlignment || "Center";
    text.style.cssText = [
      "position:absolute",
      `left:${pad.l}px`,
      `right:${pad.r}px`,
      `top:${pad.t}px`,
      `bottom:${pad.b}px`,
      "display:flex",
      `align-items:${y === "Top" ? "flex-start" : y === "Bottom" ? "flex-end" : "center"}`,
      `justify-content:${x === "Left" ? "flex-start" : x === "Right" ? "flex-end" : "center"}`,
      `font:${fontFor(node)}`,
      `color:${rgba(props.TextColor3, props.TextTransparency)}`,
      "white-space:nowrap",
      "overflow:hidden",
      "line-height:1",
    ].join(";");
    const span = document.createElement("span");
    span.style.cssText = "overflow:hidden;text-overflow:" + (props.TextTruncate === "AtEnd" ? "ellipsis" : "clip") + ";max-width:100%";
    if (props.RichText) span.innerHTML = richText(props.Text);
    else span.textContent = props.Text;
    text.appendChild(span);
    el.appendChild(text);
  }

  let container = el;
  if (props.ClipsDescendants || node.class === "ScrollingFrame") {
    container = document.createElement("div");
    container.style.cssText = "position:absolute;inset:0;overflow:hidden;";
    el.appendChild(container);
  }
  const kids = guiChildren(node)
    .map((n, i) => [n, i])
    .sort((a, b) => (a[0].props.ZIndex || 1) - (b[0].props.ZIndex || 1) || a[1] - b[1])
    .map((p) => p[0]);
  for (const kid of kids) render(kid, container, r);
  parentEl.appendChild(el);
}

// A stand-in for the Studio viewport behind the UI.
function drawViewport(root) {
  root.style.cssText = `position:relative;width:${SCREEN.x}px;height:${SCREEN.y}px;overflow:hidden;` +
    "background:linear-gradient(180deg,#6fa7e3 0%,#b9d6f2 52%,#7c8087 52%,#5d6167 100%);";
  root.innerHTML = `<svg width="${SCREEN.x}" height="${SCREEN.y}" style="position:absolute;inset:0">
    <g stroke="rgba(255,255,255,0.12)" stroke-width="1">
      ${Array.from({ length: 25 }, (_, i) => `<line x1="${SCREEN.x / 2}" y1="${SCREEN.y * 0.52}" x2="${(i - 12) * 160 + SCREEN.x / 2}" y2="${SCREEN.y}"/>`).join("")}
      ${Array.from({ length: 8 }, (_, i) => { const y = SCREEN.y * 0.52 + Math.pow(i / 7, 2) * SCREEN.y * 0.48; return `<line x1="0" y1="${y}" x2="${SCREEN.x}" y2="${y}"/>`; }).join("")}
    </g>
    <polygon points="430,470 560,430 560,330 430,370" fill="#c94f4f"/><polygon points="560,430 640,460 640,360 560,330" fill="#a63c3c"/><polygon points="430,370 560,330 640,360 510,400" fill="#e07070"/>
    <polygon points="760,440 840,420 840,250 760,270" fill="#4f8bc9"/><polygon points="840,420 890,436 890,266 840,250" fill="#3a6fa6"/><polygon points="760,270 840,250 890,266 810,286" fill="#79aee0"/>
  </svg>`;
}

// Lune encodes empty tables as {}, so normalise child lists to arrays.
(function normalise(node) {
  node.children = Array.isArray(node.children) ? node.children : [];
  node.children.forEach(normalise);
})(TREE);

const root = document.getElementById("viewport");
drawViewport(root);
TREE.rect = { x: 0, y: 0, w: SCREEN.x, h: SCREEN.y };
layoutChildren(TREE);
for (const kid of guiChildren(TREE)) render(kid, root, TREE.rect);
