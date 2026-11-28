// The catalogue site (story S.1). Renders catalog.json, which
// scripts/site-data.sh writes. No dependencies, no build step. Every value
// from the data is set as text, never as HTML.
"use strict";

const PRODUCTS = { "multi-tenant-operator": "MTO", "stakater-cloud-orchestrator": "SCO", "reloader-enterprise": "Reloader", reloader: "Reloader" };
const SIGNER = "stakater/certified-images/.github/workflows/build-certify.yaml";

function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "class") node.className = value;
    else if (key === "text") node.textContent = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function svg(path, size) {
  const ns = "http://www.w3.org/2000/svg";
  const s = document.createElementNS(ns, "svg");
  for (const [k, v] of Object.entries({ width: size, height: size, viewBox: "0 0 20 20", fill: "none", "stroke-width": "2.2", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true" })) s.setAttribute(k, v);
  const p = document.createElementNS(ns, "path");
  p.setAttribute("d", path);
  s.append(p);
  return s;
}
const tick = (size = 16) => svg("M4 10.5 8.2 14.5 16 5.5", size);

const product = (slug) => PRODUCTS[slug] || slug;
const products = (image) => image.consumers.map(product);
const latest = (image) => image.releases[0] || null;
const modules = (image) => image.deviations.reduce((n, d) => n + d.bumps.length, 0);
const fixes = (image) => image.deviations.flatMap((d) => d.fixes);
const upstreamName = (image) => image.upstream.repo.replace(/^https:\/\/github\.com\//, "");
const day = (iso) => (iso || "").slice(0, 10);

function ok(text) { return el("span", { class: "ok" }, tick(), text); }

function redhatCell(image) {
  const s = image.redhat.status;
  if (s === "listed") return el("span", { class: "strong" }, "Certified, listed by Red Hat");
  if (s === "not-listed") return el("span", { class: "bad" }, "Submitted, not listed yet");
  if (s === "not-submitted") return el("span", { class: "quiet" }, "Not submitted");
  return el("span", { class: "quiet" }, "Could not be read");
}

function copyButton(text, label, small) {
  const button = el("button", { type: "button", class: small ? "copy small" : "copy", "aria-label": label }, "Copy");
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
    } catch (e) {
      button.textContent = "Select and copy";
    }
    setTimeout(() => { button.textContent = "Copy"; }, 1800);
  });
  return button;
}

function footer(data) {
  return [
    el("span", {}, "Generated " + data.generated.replace("T", " ").replace("Z", " UTC")),
    el("span", {}, "from ", el("a", { href: data.source + "/tree/" + data.commit }, "commit " + data.commit.slice(0, 7))),
    data.offline ? el("span", { class: "bad" }, "Generated without the registry, GitHub or Red Hat: releases and statuses are not shown.") : null,
    el("span", {}, "Tests run under restricted pod security on a test cluster. Nothing here has been run on OpenShift."),
  ].filter(Boolean);
}

// ---------------------------------------------------------------- catalogue
function renderCatalog(data, root, foot) {
  const state = { product: "All", query: "" };
  const allProducts = ["All", ...Array.from(new Set(data.images.flatMap(products))).sort()];
  const patched = data.images.filter((i) => i.deviations.length > 0).length;
  const listed = data.images.filter((i) => i.redhat.status === "listed").length;

  const stats = el("dl", { class: "stats" },
    el("div", { class: "stat" }, el("dt", {}, "Images built here"), el("dd", {}, data.images.length)),
    el("div", { class: "stat" }, el("dt", {}, "Patched ahead of upstream"), el("dd", {}, patched)),
    el("div", { class: "stat" }, el("dt", {}, "Listed by Red Hat"), el("dd", {}, listed)));

  const hero = el("section", { class: "hero" },
    el("div", {},
      el("h1", {}, "Open-source images, rebuilt from source and checked before you run them"),
      el("p", { class: "lede" }, "The hardened images Stakater's products use. Each one is built from a pinned upstream commit on Red Hat UBI with the network off, tested as a running pod, scanned, signed, and published with the evidence. Each page says what was verified and what was not.")),
    stats);

  const chips = el("div", { class: "chips", role: "group", "aria-label": "Filter by product" });
  const tbody = el("tbody", {});
  const empty = el("p", { class: "quiet", hidden: "" }, "No image matches.");

  function draw() {
    chips.replaceChildren(...allProducts.map((p) => el("button", {
      type: "button", class: "chip", "aria-pressed": String(state.product === p),
      onclick: () => { state.product = p; draw(); },
    }, p)));
    const q = state.query.trim().toLowerCase();
    const rows = data.images.filter((i) =>
      (state.product === "All" || products(i).includes(state.product)) &&
      (q === "" || i.name.includes(q) || upstreamName(i).toLowerCase().includes(q) || i.tags.some((t) => t.includes(q))));
    empty.hidden = rows.length > 0;
    tbody.replaceChildren(...rows.map((i) => {
      const rel = latest(i);
      const n = modules(i);
      return el("tr", {},
        el("th", { scope: "row" },
          el("a", { class: "name", href: "image.html?name=" + encodeURIComponent(i.name) }, i.name),
          el("div", { class: "sub" }, upstreamName(i))),
        el("td", { class: "mono nowrap" }, rel ? rel.tag : "not published"),
        el("td", {}, products(i).join(", ") || "–"),
        el("td", {}, i.findings.status === "open"
          ? el("a", { class: "bad", href: i.findings.url }, "Open findings")
          : i.findings.status === "none" ? ok("None open") : el("span", { class: "quiet" }, "Could not be read")),
        el("td", {}, n > 0 ? el("span", { class: "pill blue" }, n + (n === 1 ? " module" : " modules")) : el("span", { class: "quiet" }, "Not needed")),
        el("td", {}, rel && rel.provenance === "verified" ? ok("Signed, provenance verified")
          : rel && rel.provenance === "none" ? el("span", { class: "bad" }, "No provenance")
          : el("span", { class: "quiet" }, "Could not be read")),
        el("td", {}, redhatCell(i)));
    }));
  }

  const search = el("input", { id: "q", type: "search", placeholder: "Image or upstream project", oninput: (e) => { state.query = e.target.value; draw(); } });
  const list = el("section", { id: "images", style: "display:flex;flex-direction:column;gap:16px" },
    el("div", { class: "tools" }, chips, el("div", { class: "search" }, el("label", { for: "q" }, "Search"), search)),
    el("div", { class: "table-box" }, el("table", {},
      el("thead", {}, el("tr", {}, ...["Image", "Latest release", "Used by", "Fixable critical or high CVEs", "Patched ahead of upstream", "Evidence", "Red Hat"].map((h) => el("th", { scope: "col" }, h)))),
      tbody)),
    empty,
    el("p", { class: "small" }, "Every release passed the CVE gate when it was built. \"None open\" means the daily re-scan of the newest release has no open finding. \"Listed by Red Hat\" is read from Red Hat's catalogue; an image is certified only when it appears there."));

  const stackCard = el("div", { class: "card", id: "stacks" },
    el("h2", {}, "Stacks: images tested together"),
    el("p", { style: "color:var(--ink-2)" }, "Some images only work as a set. A stack builds them from the same commit and runs them with each other on every change."),
    ...data.stacks.map((s) => el("div", { class: "inner" },
      el("div", { class: "row" }, el("strong", { style: "font-size:16px" }, s.name)),
      el("div", { class: "mono", style: "color:var(--ink-2)" }, s.images.join(" + ")))));

  const externalCard = el("div", { class: "card", id: "redhat" },
    el("h2", {}, "Used from Red Hat, not built here"),
    el("p", { style: "color:var(--ink-2)" }, "Where Red Hat ships an image we can use, we use it and say how far we could check it."),
    ...data.external.map((x) => el("div", { class: "inner" },
      el("div", { class: "row" }, el("strong", { style: "font-size:16px" }, x.name + (x.version ? " " + x.version : "")), el("span", { class: "pill warn" }, x.status)),
      el("div", { class: "mono wrap-any", style: "color:var(--ink-2)" }, x.address),
      el("div", { style: "font-size:14px;color:var(--ink-2)" }, x.note),
      x.more ? el("a", { href: x.more, style: "font-size:14px" }, "Details") : null)));

  root.replaceChildren(hero, list, el("section", { class: "pair" }, stackCard, externalCard));
  foot.replaceChildren(...footer(data));
  draw();
}

// ---------------------------------------------------------------- one image
function renderImage(data, name, root, foot, crumb) {
  const image = data.images.find((i) => i.name === name);
  if (!image) {
    root.replaceChildren(el("div", { class: "error" }, "There is no public image called \"" + name + "\". ", el("a", { href: "index.html" }, "See all images.")));
    return;
  }
  document.title = image.name + " · Stakater images";
  crumb.textContent = image.name;
  const rel = latest(image);
  const ref = rel ? image.repository + "@" + rel.digest : null;
  const n = modules(image);

  const head = el("section", { style: "display:flex;flex-direction:column;gap:16px" },
    el("div", { class: "title" },
      el("h1", {}, image.name),
      rel ? el("span", { class: "mono" }, rel.tag) : null,
      n > 0 ? el("span", { class: "pill blue" }, "Patched ahead of upstream") : null,
      el("span", { class: image.redhat.status === "listed" ? "pill blue" : "pill" },
        image.redhat.status === "listed" ? "Certified, listed by Red Hat"
          : image.redhat.status === "not-listed" ? "Submitted to Red Hat, not listed yet"
          : image.redhat.status === "not-submitted" ? "Not submitted to Red Hat" : "Red Hat status could not be read")),
    el("p", { class: "lede" }, image.description),
    ref
      ? el("div", { class: "pull" },
        el("div", { class: "hint" }, "Pull by digest. A tag can move; a digest cannot."),
        el("code", {}, ref), copyButton(ref, "Copy image reference to clipboard"))
      : el("div", { class: "error" }, "No release of this image could be read from the registry when this page was generated."));

  const tabs = el("nav", { class: "tabs", "aria-label": "Sections of this page" },
    ...[["Overview", "#checks"], ["Get started", "#start"], ["Security", "#security"], ["Releases", "#releases"], ["Source and build", "#source"]]
      .map(([label, href]) => el("a", { href }, label)));

  // What was checked. Each line is a fact about how this pipeline builds every
  // published release, or something read for this image.
  const checks = [
    ["Built from the pinned source, with the network off", "Upstream " + image.upstream.version + " at commit " + image.upstream.commit.slice(0, 12) + ". Dependencies were fetched and hash-checked first; the build itself could not download anything."],
    ["Image test", "Labels, licence files, a non-root user, and it starts as an arbitrary user in group 0."],
    [image.checks.smoke === "own-deployment" ? "Deployed and brought up under restricted pod security" : "Runs as a pod under restricted pod security",
      image.checks.smoke === "own-deployment"
        ? "This image cannot be tested as one bare pod, so it is deployed the way it is meant to run, in a namespace that enforces restricted pod security."
        : "Arbitrary UID, read-only root filesystem, no capabilities; it becomes ready, answers its health endpoint and does not restart."],
    image.checks.functional ? ["Does its job", image.checks.functional] : null,
    image.stacks.length ? ["Works with the images it is deployed with", "Part of the " + image.stacks.join(", ") + " stack: built from the same commit as the others and run together with them."] : null,
    ["CVE gate", "No fixable critical or high vulnerability when the release was built."],
    ["Red Hat certification checks, dry run", "Run on every build. Passing them is not certification; see the Red Hat status above."],
    rel && rel.provenance === "verified" ? ["Signed, with build provenance", "Checked when this page was generated: the newest release was built by this repository's pipeline from the main branch."] : null,
  ].filter(Boolean);

  const checked = el("section", { class: "card", id: "checks" },
    el("h2", {}, "What every release of this image is put through"),
    el("ul", { class: "plain" }, ...checks.map(([title, detail]) => el("li", {}, tick(20),
      el("div", { style: "min-width:0" }, el("div", { class: "strong" }, title), el("div", { class: "pre-line", style: "color:var(--ink-2);font-size:14px" }, detail))))));

  const notChecked = el("section", { class: "card warn" },
    el("h2", {}, "What was not checked"),
    el("ul", { class: "dots" },
      el("li", {}, "It has not been run on OpenShift. The tests run under restricted pod security on a test cluster, which approximates it."),
      !image.checks.functional ? el("li", {}, "It has no test of what it does, only that it starts and answers.") : null,
      image.redhat.status !== "listed" ? el("li", {}, "It is not certified by Red Hat.") : null,
      rel && rel.provenance !== "verified" ? el("li", {}, "The newest release's build provenance did not verify when this page was generated.") : null));

  const start = ref ? el("section", { class: "card", id: "start" },
    el("h2", {}, "Get started"),
    el("p", { style: "color:var(--ink-2)" }, "No login is needed. Use the digest in manifests, so what runs is exactly what was checked."),
    el("pre", {}, "docker pull " + ref),
    el("h3", {}, "Verify it yourself"),
    el("p", { style: "color:var(--ink-2)" }, "These commands check the signature, the SBOM and the build record from your own machine. cosign 3 or newer is needed; cosign 2 reports no signature."),
    el("pre", {}, [
      "REF=" + ref,
      "ID='^https://github.com/stakater/certified-images/\\.github/workflows/build-certify\\.yaml@refs/heads/main$'",
      "ISSUER=https://token.actions.githubusercontent.com",
      "",
      "cosign verify \"$REF\" --certificate-identity-regexp \"$ID\" --certificate-oidc-issuer \"$ISSUER\"",
      "cosign verify-attestation --type spdxjson \"$REF\" --certificate-identity-regexp \"$ID\" --certificate-oidc-issuer \"$ISSUER\"",
      "gh attestation verify \"oci://$REF\" --repo stakater/certified-images \\",
      "  --signer-workflow " + SIGNER,
    ].join("\n"))) : null;

  const security = el("section", { class: "card", id: "security" },
    el("h2", {}, "Security"),
    el("p", { style: "color:var(--ink-2)" },
      image.findings.status === "open" ? "The daily re-scan has open findings for the newest release: "
        : image.findings.status === "none" ? "The daily re-scan has no open finding for the newest release. "
        : "The daily re-scan's result could not be read when this page was generated. ",
      image.findings.status === "open" ? el("a", { href: image.findings.url }, "see the issue") : null,
      image.findings.status === "open" ? "." : null),
    image.deviations.length === 0
      ? el("p", { style: "color:var(--ink-2)" }, "This image is built from upstream's release as it is: no dependency needed patching to pass the CVE gate.")
      : [
        el("p", { style: "color:var(--ink-2)" }, "Upstream's release carried " + fixes(image).length + (fixes(image).length === 1 ? " finding" : " findings") + " that this image fixes by using newer versions of its dependencies. Nothing else in the source is changed."),
        el("div", { class: "table-box" }, el("table", {},
          el("thead", {}, el("tr", {}, ...["Dependency", "Fixes", "Offered upstream"].map((h) => el("th", { scope: "col" }, h)))),
          el("tbody", {}, ...image.deviations.map((d) => el("tr", {},
            el("td", { class: "mono" }, ...d.bumps.map((b) => el("div", {}, b))),
            el("td", { class: "mono" }, ...d.fixes.map((f) => el("div", {}, f))),
            el("td", {}, /^https?:/.test(d.upstreamPR || "") ? el("a", { href: d.upstreamPR }, "Pull request") : /none yet/i.test(d.upstreamPR || "") ? el("span", { class: "bad" }, "Not yet") : el("span", { class: "quiet" }, d.upstreamPR || "–"))))))),
      ]);

  const releases = el("section", { class: "card", id: "releases" },
    el("h2", {}, "Releases"),
    el("p", { style: "color:var(--ink-2)" }, "A release is never changed or removed. A release without verified provenance was pushed but not signed; use a newer one."),
    image.releases.length === 0
      ? el("p", { class: "quiet" }, "No release could be read.")
      : el("div", { class: "table-box" }, el("table", {},
        el("thead", {}, el("tr", {}, ...["Release", "Digest", "Build provenance"].map((h) => el("th", { scope: "col" }, h)))),
        el("tbody", {}, ...image.releases.map((r) => el("tr", {},
          el("td", { class: "mono nowrap" }, r.tag),
          el("td", {}, el("span", { class: "mono wrap-any" }, r.digest), " ", copyButton(image.repository + "@" + r.digest, "Copy the reference of " + r.tag, true)),
          el("td", {}, r.provenance === "verified" ? ok("Verified") : r.provenance === "none" ? el("span", { class: "bad" }, "Not signed") : el("span", { class: "quiet" }, "Could not be read"))))))));

  const facts = el("section", { class: "card", id: "source" },
    el("h2", {}, "Source and build"),
    el("dl", { class: "facts" },
      el("div", {}, el("dt", {}, "Upstream"), el("dd", {}, el("a", { href: image.upstream.repo }, upstreamName(image)), ", tag " + image.upstream.version)),
      el("div", {}, el("dt", {}, "Pinned commit"), el("dd", { class: "mono wrap-any" }, image.upstream.commit)),
      el("div", {}, el("dt", {}, "Base image"), el("dd", {}, image.base.image, el("div", { class: "mono wrap-any small" }, image.base.digest))),
      image.toolchain ? el("div", {}, el("dt", {}, "Toolchain"), el("dd", {}, image.toolchain)) : null,
      el("div", {}, el("dt", {}, "Licence"), el("dd", {}, image.upstream.license)),
      el("div", {}, el("dt", {}, "Used by"), el("dd", {}, products(image).join(", ") || "–")),
      el("div", {}, el("dt", {}, "Registry"), el("dd", { class: "mono wrap-any" }, image.repository)),
      image.redhat.address ? el("div", {}, el("dt", {}, "Red Hat's address"), el("dd", { class: "mono wrap-any" }, image.redhat.address)) : null),
    el("a", { href: data.source + "/tree/main/images/" + image.name }, "How it is built: the image's files"));

  root.replaceChildren(head, tabs,
    el("div", { class: "cols" },
      el("div", { class: "main" }, checked, notChecked, start, security, releases),
      el("aside", { "aria-label": "Facts about this image" }, facts)));
  foot.replaceChildren(...footer(data));
}

// ---------------------------------------------------------------- start
async function main() {
  const root = document.getElementById("app");
  const foot = document.getElementById("foot");
  try {
    const response = await fetch("catalog.json", { cache: "no-cache" });
    if (!response.ok) throw new Error("catalog.json: HTTP " + response.status);
    const data = await response.json();
    if (document.body.dataset.page === "image") {
      renderImage(data, new URLSearchParams(location.search).get("name") || "", root, foot, document.getElementById("crumb"));
    } else {
      renderCatalog(data, root, foot);
    }
  } catch (e) {
    root.replaceChildren(el("div", { class: "error" }, "The catalogue data could not be loaded (" + e.message + ")."));
  }
}
main();
