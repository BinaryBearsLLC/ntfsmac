const releaseLink = document.querySelector("#release-link");
const releaseStatus = document.querySelector("#release-status");
const root = document.documentElement;
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

fetch("https://api.github.com/repos/BinaryBearsLLC/ntfsmac/releases/latest", {
  headers: { Accept: "application/vnd.github+json" }
})
  .then((response) => {
    if (!response.ok) throw new Error("No published release");
    return response.json();
  })
  .then((release) => {
    if (!release || release.draft || release.prerelease || !release.html_url) return;
    releaseLink.href = release.html_url;
    releaseLink.textContent = `Get ${release.tag_name}`;
    releaseStatus.textContent = `Latest published release: ${release.tag_name}`;
  })
  .catch(() => {
    // The static latest-release link and status remain useful offline or under API limits.
  });

if (!reducedMotion.matches && "IntersectionObserver" in window) {
  root.classList.add("motion-ready");

  document.querySelectorAll("[data-reveal-group]").forEach((group) => {
    [...group.children].forEach((child, index) => {
      child.style.setProperty("--reveal-delay", `${Math.min(index * 85, 340)}ms`);
    });
  });

  document.querySelectorAll(".steps [data-reveal]").forEach((card, index) => {
    card.style.setProperty("--reveal-delay", `${index * 90}ms`);
  });

  const revealObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.14, rootMargin: "0px 0px -7%" });

  document.querySelectorAll("[data-reveal], [data-reveal-group]").forEach((element) => {
    revealObserver.observe(element);
  });
}

let scrollFrame;
const updateScrollEffects = () => {
  const maximum = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
  const progress = Math.min(Math.max(window.scrollY / maximum, 0), 1);
  root.style.setProperty("--scroll-progress", progress.toFixed(4));
  root.style.setProperty("--hero-scroll", `${Math.min(window.scrollY * 0.055, 28)}px`);
  scrollFrame = undefined;
};

window.addEventListener("scroll", () => {
  if (!scrollFrame) scrollFrame = requestAnimationFrame(updateScrollEffects);
}, { passive: true });
updateScrollEffects();

if (!reducedMotion.matches && window.matchMedia("(pointer: fine)").matches) {
  const hero = document.querySelector(".hero");
  hero.addEventListener("pointermove", (event) => {
    const bounds = hero.getBoundingClientRect();
    const x = ((event.clientX - bounds.left) / bounds.width - .5) * 14;
    const y = ((event.clientY - bounds.top) / bounds.height - .5) * 10;
    root.style.setProperty("--pointer-x", `${x.toFixed(2)}px`);
    root.style.setProperty("--pointer-y", `${y.toFixed(2)}px`);
  });
  hero.addEventListener("pointerleave", () => {
    root.style.setProperty("--pointer-x", "0px");
    root.style.setProperty("--pointer-y", "0px");
  });
}
