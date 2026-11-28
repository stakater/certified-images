// The catalogue site (story S.1). Renders what scripts/site-data.sh writes:
// catalog.json, and details/<name>.json for one image's page. No dependencies,
// no build step. Every value from the data is set as text, never as HTML.
"use strict";

const PRODUCTS = { "multi-tenant-operator": "MTO", "stakater-cloud-orchestrator": "SCO", "reloader-enterprise": "Reloader", reloader: "Reloader" };
const SIGNER = "stakater/certified-images/.github/workflows/build-certify.yaml";
const SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"];
const MAX_ROWS = 300;

function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? "" : value);
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function svg(path, size) {
  const ns = "http://www.w3.org/2000/svg";
  const s = document.createElementNS(ns, "svg");
  for (const [k, v] of Object.entries({ width: size, height: size, viewBox: "0 0 20 20", fill: "none", "stroke-width": "2.2", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true" })) s.setAttribute(k, v);
  const path1 = document.createElementNS(ns, "path");
  path1.setAttribute("d", path);
  s.append(path1);
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
const when = (iso) => (iso || "").slice(0, 16).replace("T", " ") + " UTC";
const megabytes = (bytes) => (bytes ? Math.round(bytes / 1048576) + " MB" : "–");
const plural = (n, one, many) => n + " " + (n === 1 ? one : many);

function ok(text) { return el("span", { class: "ok" }, tick(), text); }
function para(text, ...more) { return el("p", { class: "soft" }, text, ...more); }

function redhatText(image) {
  const s = image.redhat.status;
  if (s === "listed") return "Certified, listed by Red Hat";
  if (s === "not-listed") return "Submitted to Red Hat, not listed yet";
  if (s === "not-submitted") return "Not submitted to Red Hat";
  return "Red Hat status could not be read";
}
function redhatCell(image) {
  const s = image.redhat.status;
  return el("span", { class: s === "listed" ? "strong" : s === "not-listed" ? "bad" : "quiet" }, redhatText(image).replace(" to Red Hat", ""));
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

function table(headers, rows, cls) {
  return el("div", { class: "table-box" }, el("table", { class: cls || null },
    el("thead", {}, el("tr", {}, headers.map((h) => el("th", { scope: "col" }, h)))),
    el("tbody", {}, rows)));
}

function footer(data) {
  return [
    el("span", {}, "Generated " + when(data.generated)),
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
  const empty = el("p", { class: "quiet", hidden: true }, "No image matches.");

  function draw() {
    chips.replaceChildren(...allProducts.map((name) => el("button", {
      type: "button", class: "chip", "aria-pressed": String(state.product === name),
      onclick: () => { state.product = name; draw(); },
    }, name)));
    const q = state.query.trim().toLowerCase();
    const rows = data.images.filter((i) =>
      (state.product === "All" || products(i).includes(state.product)) &&
      (q === "" || i.name.includes(q) || upstreamName(i).toLowerCase().includes(q) || i.tags.some((t) => t.includes(q))));
    empty.hidden = rows.length > 0;
    tbody.replaceChildren(...rows.map((i) => {
      const rel = latest(i);
      const n = modules(i);
      const href = "image.html?name=" + encodeURIComponent(i.name);
      const scan = i.scan && i.scan.status === "scanned" ? i.scan : null;
      return el("tr", {},
        el("th", { scope: "row" },
          el("a", { class: "name", href }, i.name),
          el("div", { class: "sub" }, upstreamName(i))),
        el("td", {}, el("span", { class: "mono nowrap" }, rel ? rel.tag : "not published"),
          i.container ? el("div", { class: "sub" }, megabytes(i.container.size) + " · " + i.container.architecture) : null),
        el("td", {}, products(i).join(", ") || "–"),
        el("td", {},
          scan
            ? [scan.fixableCriticalHigh === 0 ? ok("No fixable critical or high") : el("span", { class: "bad" }, scan.fixableCriticalHigh + " fixable critical or high"),
              el("div", { class: "sub" }, el("a", { href: href + "#cves" }, scan.total + " detected in all"))]
            : el("span", { class: "quiet" }, "Scan could not be read"),
          i.findings.status === "open" ? el("div", {}, el("a", { class: "bad", href: i.findings.url }, "Open re-scan finding")) : null),
        el("td", {}, n > 0 ? el("span", { class: "pill blue" }, plural(n, "module", "modules")) : el("span", { class: "quiet" }, "Not needed")),
        el("td", {}, i.signature === "verified" && rel && rel.provenance === "verified" ? ok("Signed, provenance verified")
          : i.signature === "unknown" || !rel || rel.provenance === "unknown" ? el("span", { class: "quiet" }, "Could not be read")
          : el("span", { class: "bad" }, "Not fully verified")),
        el("td", {}, redhatCell(i)));
    }));
  }

  const search = el("input", { id: "q", type: "search", placeholder: "Image or upstream project", oninput: (e) => { state.query = e.target.value; draw(); } });
  const list = el("section", { id: "images", class: "stack" },
    el("div", { class: "tools" }, chips, el("div", { class: "search" }, el("label", { for: "q" }, "Search"), search)),
    el("div", { class: "table-box" }, el("table", { class: "wide" },
      el("thead", {}, el("tr", {}, ["Image", "Latest release", "Used by", "Vulnerabilities", "Patched ahead of upstream", "Evidence", "Red Hat"].map((h) => el("th", { scope: "col" }, h)))),
      tbody)),
    empty,
    el("p", { class: "small" }, "Vulnerabilities are from a scan of the newest release, made when this page was generated. \"Fixable critical or high\" is what the build gate refuses; \"detected in all\" counts every severity, including ones with no fix available. An image is certified only when Red Hat's catalogue lists it."));

  const stackCard = el("div", { class: "card", id: "stacks" },
    el("h2", {}, "Stacks: images tested together"),
    para("Some images only work as a set. A stack builds them from the same commit and runs them with each other on every change."),
    data.stacks.map((s) => el("div", { class: "inner" },
      el("strong", { class: "big" }, s.name),
      el("div", { class: "mono soft" }, s.images.join(" + ")))));

  const externalCard = el("div", { class: "card", id: "redhat" },
    el("h2", {}, "Used from Red Hat, not built here"),
    para("Where Red Hat ships an image we can use, we use it and say how far we could check it."),
    data.external.map((x) => el("div", { class: "inner" },
      el("div", { class: "row" }, el("strong", { class: "big" }, x.name + (x.version ? " " + x.version : "")), el("span", { class: "pill warn" }, x.status)),
      el("div", { class: "mono wrap-any soft" }, x.address),
      el("div", { class: "soft", style: "font-size:14px" }, x.note),
      x.more ? el("a", { href: x.more, style: "font-size:14px" }, "Details") : null)));

  root.replaceChildren(hero, list, el("section", { class: "pair" }, stackCard, externalCard));
  foot.replaceChildren(...footer(data));
  draw();
}

// ---------------------------------------------------------------- one image
function overviewTab(image, rel) {
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
  ].filter(Boolean);
  return [
    el("section", { class: "card" },
      el("h2", {}, "What every release of this image is put through"),
      el("ul", { class: "plain" }, checks.map(([title, detail]) => el("li", {}, tick(20),
        el("div", { class: "grow" }, el("div", { class: "strong" }, title), el("div", { class: "pre-line soft", style: "font-size:14px" }, detail)))))),
    el("section", { class: "card warn" },
      el("h2", {}, "What was not checked"),
      el("ul", { class: "dots" },
        el("li", {}, "It has not been run on OpenShift. The tests run under restricted pod security on a test cluster, which approximates it."),
        !image.checks.functional ? el("li", {}, "It has no test of what it does, only that it starts and answers.") : null,
        image.redhat.status !== "listed" ? el("li", {}, "It is not certified by Red Hat.") : null,
        rel && rel.provenance !== "verified" ? el("li", {}, "The newest release's build provenance did not verify when this page was generated.") : null)),
  ];
}

function containerTab(image, details, data) {
  const c = details.container;
  const fact = (name, value, mono) => (value === null || value === undefined || value === "" ? null
    : el("div", {}, el("dt", {}, name), el("dd", { class: mono ? "mono wrap-any" : null }, value)));
  const labels = c ? Object.entries(c.labels).sort(([a], [b]) => a.localeCompare(b)) : [];
  return [
    el("section", { class: "card" },
      el("h2", {}, "Container details"),
      c ? null : para("The container's configuration could not be read from the registry when this page was generated."),
      el("dl", { class: "facts two" },
        c ? fact("Architecture", c.os + "/" + c.architecture) : null,
        c ? fact("Compressed size", megabytes(c.size) + " in " + plural(c.layers, "layer", "layers")) : null,
        c ? fact("Built", when(c.created)) : null,
        c ? fact("Runs as", "UID " + c.user + " (any UID in group 0 also works)") : null,
        c ? fact("Entrypoint", c.entrypoint.join(" "), true) : null,
        c && c.command.length ? fact("Default command", c.command.join(" "), true) : null,
        c && c.ports.length ? fact("Ports", c.ports.join(", "), true) : null,
        c && c.workdir ? fact("Working directory", c.workdir, true) : null,
        fact("Base image", el("span", {}, image.base.image, el("div", { class: "mono wrap-any small" }, image.base.digest))),
        fact("Toolchain", image.toolchain),
        fact("Licence", image.upstream.license),
        fact("Used by", products(image).join(", ")),
        fact("Registry", image.repository, true),
        image.redhat.address ? fact("Red Hat's address", image.redhat.address, true) : null)),
    el("section", { class: "card" },
      el("h2", {}, "Source"),
      el("dl", { class: "facts two" },
        fact("Upstream", el("span", {}, el("a", { href: image.upstream.repo }, upstreamName(image)), ", tag " + image.upstream.version)),
        fact("Pinned commit", image.upstream.commit, true)),
      el("a", { href: data.source + "/tree/main/images/" + image.name }, "How it is built: the image's files")),
    labels.length ? el("section", { class: "card" },
      el("h2", {}, "Labels"),
      table(["Label", "Value"], labels.map(([k, v]) => el("tr", {}, el("td", { class: "mono" }, k), el("td", { class: "wrap-any" }, v))))) : null,
  ];
}

function tagsTab(image) {
  const tbody = el("tbody", {});
  const note = el("p", { class: "quiet", hidden: true }, "No release matches.");
  function draw(q) {
    const rows = image.releases.filter((r) => q === "" || r.tag.toLowerCase().includes(q) || r.digest.includes(q));
    note.hidden = rows.length > 0;
    tbody.replaceChildren(...rows.map((r) => el("tr", {},
      el("td", { class: "mono nowrap" }, r.tag),
      el("td", {}, el("span", { class: "mono wrap-any" }, r.digest), " ", copyButton(image.repository + "@" + r.digest, "Copy the reference of " + r.tag, true)),
      el("td", {}, r.provenance === "verified" ? ok("Verified") : r.provenance === "none" ? el("span", { class: "bad" }, "Not signed") : el("span", { class: "quiet" }, "Could not be read")))));
  }
  draw("");
  return [el("section", { class: "card" },
    el("h2", {}, "Tags"),
    para("A tag is the upstream version, a dash, and our release number. The number goes up each time we rebuild the same upstream version, and starts again at 1 with a new one. A release is never changed or removed. One without verified provenance was pushed but not signed; use a newer one."),
    image.releases.length === 0 ? para("No release could be read from the registry.") : [
      el("div", { class: "search" }, el("label", { for: "tag-q" }, "Search tags"), el("input", { id: "tag-q", type: "search", placeholder: "Tag or digest", oninput: (e) => draw(e.target.value.trim().toLowerCase()) })),
      el("div", { class: "table-box" }, el("table", {}, el("thead", {}, el("tr", {}, ["Release", "Digest", "Build provenance"].map((h) => el("th", { scope: "col" }, h)))), tbody)),
      note,
    ])];
}

function sbomTab(image, details) {
  const sbom = details.sbom;
  if (sbom.status !== "verified") {
    return [el("section", { class: "card" }, el("h2", {}, "SBOM"),
      para(sbom.status === "none" ? "No signed SBOM could be verified for the newest release." : "The SBOM could not be read when this page was generated."))];
  }
  const packages = sbom.packages || [];
  const types = Array.from(new Set(packages.map((x) => x.t))).sort();
  const state = { q: "", type: "" };
  const tbody = el("tbody", {});
  const count = el("p", { class: "small" });
  function draw() {
    const rows = packages.filter((x) => (state.type === "" || x.t === state.type) && (state.q === "" || x.n.toLowerCase().includes(state.q) || x.v.toLowerCase().includes(state.q)));
    count.textContent = (rows.length === packages.length ? plural(packages.length, "package", "packages") : rows.length + " of " + plural(packages.length, "package", "packages")) +
      (rows.length > MAX_ROWS ? ". The first " + MAX_ROWS + " are shown; search to narrow." : "");
    tbody.replaceChildren(...rows.slice(0, MAX_ROWS).map((x) => el("tr", {},
      el("td", { class: "mono wrap-any" }, x.n), el("td", { class: "mono wrap-any" }, x.v || "–"), el("td", {}, x.t), el("td", { class: "wrap-any" }, x.l || "–"))));
  }
  draw();
  const file = (kind) => sbom.files.find((f) => f.kind === kind);
  const download = (kind, label) => (file(kind) ? el("a", { class: "button", href: file(kind).file, download: true }, label) : null);
  return [el("section", { class: "card" },
    el("div", { class: "row" }, el("h2", {}, "SBOM"),
      el("div", { class: "chips" }, download("image", "Download SPDX: the image"), download("dependencies", "Download SPDX: build inputs"))),
    para("What is in the newest release, from the SBOM that the pipeline signed and attached to the image. Its signature was verified when this page was generated. The second file lists what the build was given: every dependency fetched before the network was switched off."),
    file("image") ? el("p", { class: "small" }, "Made by " + file("image").tool + ".") : null,
    el("div", { class: "tools" },
      el("div", { class: "search" }, el("label", { for: "sbom-q" }, "Search"), el("input", { id: "sbom-q", type: "search", placeholder: "Package or version", oninput: (e) => { state.q = e.target.value.trim().toLowerCase(); draw(); } })),
      el("div", { class: "search" }, el("label", { for: "sbom-t" }, "Type"),
        el("select", { id: "sbom-t", onchange: (e) => { state.type = e.target.value; draw(); } }, el("option", { value: "" }, "All types"), types.map((t) => el("option", { value: t }, t))))),
    count,
    el("div", { class: "table-box" }, el("table", {}, el("thead", {}, el("tr", {}, ["Package", "Version", "Type", "Licence"].map((h) => el("th", { scope: "col" }, h)))), tbody)))];
}

function verifyTab(image, details, rel, ref) {
  const line = (good, unknown, yes, no, dunno) => el("li", {}, good ? tick(20) : el("span", { class: "dash", "aria-hidden": "true" }, "–"),
    el("div", { class: "grow" }, good ? yes : unknown ? dunno : no));
  return [el("section", { class: "card" },
    el("h2", {}, "Verify build"),
    para("Checked for the newest release when this page was generated:"),
    el("ul", { class: "plain" },
      line(details.signature === "verified", details.signature === "unknown", "Its signature verifies: signed by this repository's pipeline, from the main branch.", "Its signature did not verify.", "Its signature could not be checked."),
      line(details.sbom.status === "verified", details.sbom.status === "unknown", "Its SBOM attestations verify, signed the same way.", "No SBOM attestation verified.", "Its SBOM attestations could not be checked."),
      line(rel && rel.provenance === "verified", !rel || rel.provenance === "unknown", "Its build provenance verifies: which workflow run built it, from which commit.", "Its build provenance did not verify.", "Its build provenance could not be checked.")),
    ref ? [
      el("h3", {}, "Check it yourself"),
      para("You do not have to take this page's word. cosign 3 or newer is needed; cosign 2 reports no signature for these images."),
      el("pre", {}, [
        "REF=" + ref,
        "ID='^https://github.com/stakater/certified-images/\\.github/workflows/build-certify\\.yaml@refs/heads/main$'",
        "ISSUER=https://token.actions.githubusercontent.com",
        "",
        "cosign verify \"$REF\" --certificate-identity-regexp \"$ID\" --certificate-oidc-issuer \"$ISSUER\"",
        "cosign verify-attestation --type spdxjson \"$REF\" --certificate-identity-regexp \"$ID\" --certificate-oidc-issuer \"$ISSUER\"",
        "gh attestation verify \"oci://$REF\" --repo stakater/certified-images \\",
        "  --signer-workflow " + SIGNER,
      ].join("\n")),
    ] : null)];
}

function cveTab(image, details, data, ref) {
  const scan = details.scan;
  const scanned = scan.status === "scanned";
  const findings = scanned ? scan.findings : [];
  const state = { q: "", severity: "", fixable: false };
  const tbody = el("tbody", {});
  const count = el("p", { class: "small" });
  function draw() {
    const rows = findings.filter((f) => (state.severity === "" || f.severity === state.severity) && (!state.fixable || f.fixed !== "") &&
      (state.q === "" || f.id.toLowerCase().includes(state.q) || f.pkg.toLowerCase().includes(state.q)));
    count.textContent = rows.length + " of " + plural(findings.length, "finding", "findings") + (rows.length > MAX_ROWS ? ". The first " + MAX_ROWS + " are shown." : "");
    tbody.replaceChildren(...rows.slice(0, MAX_ROWS).map((f) => el("tr", {},
      el("td", { class: "mono nowrap" }, f.id),
      el("td", {}, el("span", { class: "sev sev-" + f.severity.toLowerCase() }, f.severity.toLowerCase())),
      el("td", { class: "mono wrap-any" }, f.pkg, el("div", { class: "sub" }, f.kind)),
      el("td", { class: "mono wrap-any" }, f.installed),
      el("td", { class: "mono wrap-any" }, f.fixed || el("span", { class: "quiet" }, "no fix yet")),
      el("td", { class: "wrap-any", style: "font-size:13px" }, f.title))));
  }
  if (scanned) draw();
  const n = fixes(image).length;
  return [
    el("section", { class: "card" },
      el("h2", {}, "Current scan"),
      scanned ? [
        para("Scanned with " + scan.scanner + " on " + when(scan.scannedAt) + ". This counts every severity, including vulnerabilities in the base image that have no fix available yet."),
        el("div", { class: "chips" }, SEVERITIES.filter((s) => scan.bySeverity[s]).map((s) => el("span", { class: "sev big sev-" + s.toLowerCase() }, scan.bySeverity[s] + " " + s.toLowerCase()))),
        para("Fixable, critical or high: ", el("strong", {}, String(scan.fixableCriticalHigh)), ". That is the line the build gate holds: a release with one of those is not published. The daily re-scan opens an issue when a published release crosses it."),
      ] : para("The newest release could not be scanned when this page was generated. That is not a clean result."),
      image.findings.status === "open" ? para("The daily re-scan has an open finding: ", el("a", { href: image.findings.url }, "see the issue"), ".") : null),
    el("section", { class: "card" },
      el("h2", {}, "Patched ahead of upstream"),
      image.deviations.length === 0
        ? para("This image is built from upstream's release as it is: no dependency needed patching to pass the CVE gate.")
        : [para("Upstream's release carried " + plural(n, "finding", "findings") + " that this image fixes by using newer versions of its dependencies. Nothing else in the source is changed."),
          table(["Dependency", "Fixes", "Offered upstream"], image.deviations.map((d) => el("tr", {},
            el("td", { class: "mono" }, d.bumps.map((b) => el("div", {}, b))),
            el("td", { class: "mono" }, d.fixes.map((f) => el("div", {}, f))),
            el("td", {}, /^https?:/.test(d.upstreamPR || "") ? el("a", { href: d.upstreamPR }, "Pull request")
              : /none yet/i.test(d.upstreamPR || "") ? el("span", { class: "bad" }, "Not yet") : el("span", { class: "quiet" }, d.upstreamPR || "–")))))]),
    scanned && findings.length ? el("section", { class: "card" },
      el("h2", {}, "Findings"),
      el("div", { class: "tools" },
        el("div", { class: "search" }, el("label", { for: "cve-q" }, "Search"), el("input", { id: "cve-q", type: "search", placeholder: "CVE or package", oninput: (e) => { state.q = e.target.value.trim().toLowerCase(); draw(); } })),
        el("div", { class: "search" }, el("label", { for: "cve-s" }, "Severity"),
          el("select", { id: "cve-s", onchange: (e) => { state.severity = e.target.value; draw(); } }, el("option", { value: "" }, "All"), SEVERITIES.filter((s) => scan.bySeverity[s]).map((s) => el("option", { value: s }, s.toLowerCase())))),
        el("label", { class: "check" }, el("input", { type: "checkbox", onchange: (e) => { state.fixable = e.target.checked; draw(); } }), "Only with a fix available")),
      count,
      el("div", { class: "table-box" }, el("table", { class: "wide" }, el("thead", {}, el("tr", {}, ["Finding", "Severity", "Package", "Installed", "Fixed in", "About"].map((h) => el("th", { scope: "col" }, h)))), tbody))) : null,
    el("section", { class: "card" },
      el("h2", {}, "Scan it yourself, or report a problem"),
      ref ? el("pre", {}, "trivy image " + ref) : null,
      para("Found something we missed? ", el("a", { href: data.source + "/security/advisories/new" }, "Report a vulnerability privately"), " or ", el("a", { href: data.source + "/issues/new" }, "open an issue"), ".")),
  ];
}

function renderImage(data, details, name, root, foot, crumb) {
  const image = data.images.find((i) => i.name === name);
  if (!image) {
    root.replaceChildren(el("div", { class: "error" }, "There is no public image called \"" + name + "\". ", el("a", { href: "index.html" }, "See all images.")));
    return;
  }
  document.title = image.name + " · Stakater images";
  crumb.textContent = image.name;
  const rel = latest(image);
  const ref = rel ? image.repository + "@" + rel.digest : null;
  const scan = image.scan && image.scan.status === "scanned" ? image.scan : null;

  const tabs = [
    ["overview", "Overview", () => overviewTab(image, rel)],
    ["container", "Container details", () => containerTab(image, details, data)],
    ["tags", "Tags", () => tagsTab(image)],
    ["sbom", "SBOM", () => sbomTab(image, details)],
    ["verify", "Verify build", () => verifyTab(image, details, rel, ref)],
    ["cves", "CVEs", () => cveTab(image, details, data, ref)],
  ];
  const panel = el("div", { class: "stack", role: "tabpanel", id: "panel", tabindex: "0" });
  const tablist = el("div", { class: "tabs", role: "tablist", "aria-label": "Sections of this image" });
  function show(id, focus) {
    const current = tabs.find(([key]) => key === id) || tabs[0];
    const go = (key) => { history.replaceState(null, "", "#" + key); show(key, true); };
    tablist.replaceChildren(...tabs.map(([key, label], i) => el("button", {
      type: "button", role: "tab", id: "tab-" + key, "aria-selected": String(key === current[0]), "aria-controls": "panel",
      tabindex: key === current[0] ? "0" : "-1",
      onclick: () => go(key),
      onkeydown: (e) => {
        if (e.key === "ArrowRight") go(tabs[(i + 1) % tabs.length][0]);
        if (e.key === "ArrowLeft") go(tabs[(i + tabs.length - 1) % tabs.length][0]);
      },
    }, label)));
    panel.setAttribute("aria-labelledby", "tab-" + current[0]);
    panel.replaceChildren(...current[2]().flat(Infinity).filter(Boolean));
    if (focus) document.getElementById("tab-" + current[0]).focus();
  }
  const fromHash = () => (location.hash || "#overview").slice(1);

  const cveCard = el("a", { class: "cve-card" + (scan && scan.fixableCriticalHigh > 0 ? " alert" : ""), href: "#cves" },
    scan
      ? [el("div", { class: "cve-count" }, plural(scan.total, "CVE detected", "CVEs detected")),
        el("div", { class: "strong" }, scan.fixableCriticalHigh === 0 ? "None is a fixable critical or high" : scan.fixableCriticalHigh + " fixable critical or high"),
        el("div", { class: "small" }, scan.scanner + " · last scanned " + when(scan.scannedAt))]
      : [el("div", { class: "cve-count" }, "Not scanned"), el("div", { class: "small" }, "The newest release could not be scanned when this page was generated. That is not a clean result.")]);

  const head = el("section", { class: "stack" },
    el("div", { class: "title" },
      el("h1", {}, image.name),
      rel ? el("span", { class: "mono" }, rel.tag) : null,
      modules(image) > 0 ? el("span", { class: "pill blue" }, "Patched ahead of upstream") : null,
      el("span", { class: image.redhat.status === "listed" ? "pill blue" : "pill" }, redhatText(image))),
    el("p", { class: "lede" }, image.description),
    el("div", { class: "headline" },
      el("dl", { class: "facts grid" },
        el("div", {}, el("dt", {}, "Architecture"), el("dd", {}, image.container ? image.container.architecture : "–")),
        el("div", {}, el("dt", {}, "Stream"), el("dd", {}, el("span", { class: "pill" }, image.upstream.version))),
        el("div", {}, el("dt", {}, "Size"), el("dd", {}, image.container ? megabytes(image.container.size) : "–")),
        el("div", {}, el("dt", {}, "Last built"), el("dd", {}, image.container ? day(image.container.created) : "–")),
        el("div", {}, el("dt", {}, "Used by"), el("dd", {}, products(image).join(", ") || "–")),
        el("div", {}, el("dt", {}, "Licence"), el("dd", {}, image.upstream.license))),
      cveCard),
    ref
      ? el("div", { class: "pull" },
        el("div", { class: "hint" }, "Pull by digest. A tag can move; a digest cannot. No login is needed."),
        el("code", {}, ref), copyButton(ref, "Copy image reference to clipboard"))
      : el("div", { class: "error" }, "No release of this image could be read from the registry when this page was generated."));

  root.replaceChildren(head, tablist, panel);
  foot.replaceChildren(...footer(data));
  show(fromHash(), false);
  window.addEventListener("hashchange", () => show(fromHash(), false));
}

// ---------------------------------------------------------------- start
async function getJSON(path) {
  const response = await fetch(path, { cache: "no-cache" });
  if (!response.ok) throw new Error(path + ": HTTP " + response.status);
  return response.json();
}

async function main() {
  const root = document.getElementById("app");
  const foot = document.getElementById("foot");
  try {
    const data = await getJSON("catalog.json");
    if (document.body.dataset.page === "image") {
      const name = new URLSearchParams(location.search).get("name") || "";
      const known = data.images.some((i) => i.name === name);
      const details = known ? await getJSON("details/" + encodeURIComponent(name) + ".json") : null;
      renderImage(data, details, name, root, foot, document.getElementById("crumb"));
    } else {
      renderCatalog(data, root, foot);
    }
  } catch (e) {
    root.replaceChildren(el("div", { class: "error" }, "The catalogue data could not be loaded (" + e.message + ")."));
  }
}
main();
