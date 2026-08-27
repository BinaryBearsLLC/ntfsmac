const releaseLink = document.querySelector("#release-link");
const releaseStatus = document.querySelector("#release-status");
const root = document.documentElement;
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const impactLab = document.querySelector("[data-impact-lab]");
const impactScenarios = {
  idle: {
    kicker: "At rest",
    title: "Barely there.",
    copy: "The menu stays ready while ntfsmac settles into a slower background rhythm.",
    cpu: "<0.002%",
    memory: "~30 MB",
    memoryShare: "0.12%",
    battery: "Near-zero",
    ariaLabel: "At rest: less than 0.002 percent CPU and about 30 megabytes of memory",
    cpuLevel: "12%",
    memoryLevel: "12%",
    speed: "8s",
    verdict: "Quiet by design.",
    verdictCopy: "Enough headroom that ordinary use stays comfortably below one percent of a CPU core and system memory."
  },
  open: {
    kicker: "Menu open",
    title: "Responsive, still tiny.",
    copy: "Fresh drive information and live controls arrive without turning the menu into a heavyweight app.",
    cpu: "<0.006%",
    memory: "~34 MB",
    memoryShare: "0.14%",
    battery: "Near-zero",
    ariaLabel: "Menu open: less than 0.006 percent CPU and about 34 megabytes of memory",
    cpuLevel: "59%",
    memoryLevel: "14%",
    speed: "5.5s",
    verdict: "Fast when visible.",
    verdictCopy: "Opening the menu increases responsiveness, not resource pressure."
  },
  mounted: {
    kicker: "Drive mounted",
    title: "More capability. Less than 1% memory.",
    copy: "The private filesystem runtime joins in only while your drive is mounted, then leaves when you unmount.",
    cpu: "<0.004%",
    memory: "~200 MB",
    memoryShare: "0.82%",
    battery: "Very low",
    ariaLabel: "Drive mounted: less than 0.004 percent CPU and about 200 megabytes of memory",
    cpuLevel: "34%",
    memoryLevel: "82%",
    speed: "4.2s",
    verdict: "Headroom to spare.",
    verdictCopy: "Even the complete mounted stack remains below one percent of the test Mac's memory."
  }
};

const updateImpactScenario = (scenarioName) => {
  if (!impactLab || !impactScenarios[scenarioName]) return;
  const scenario = impactScenarios[scenarioName];
  impactLab.dataset.impactScenario = scenarioName;
  impactLab.style.setProperty("--impact-cpu", scenario.cpuLevel);
  impactLab.style.setProperty("--impact-memory", scenario.memoryLevel);
  impactLab.style.setProperty("--impact-speed", scenario.speed);
  impactLab.querySelector("[data-impact-kicker]").textContent = scenario.kicker;
  impactLab.querySelector("[data-impact-title]").textContent = scenario.title;
  impactLab.querySelector("[data-impact-copy]").textContent = scenario.copy;
  impactLab.querySelector("[data-impact-cpu]").textContent = scenario.cpu;
  impactLab.querySelector("[data-impact-memory]").textContent = scenario.memory;
  impactLab.querySelector("[data-impact-battery]").textContent = scenario.battery;
  impactLab.querySelector("[data-impact-cpu-label]").textContent = scenario.cpu;
  impactLab.querySelector("[data-impact-memory-label]").textContent = scenario.memoryShare;
  impactLab.querySelector("[data-impact-verdict]").textContent = scenario.verdict;
  impactLab.querySelector("[data-impact-verdict-copy]").textContent = scenario.verdictCopy;
  impactLab.querySelector("[data-impact-chart]").setAttribute("aria-label", scenario.ariaLabel);
  impactLab.querySelectorAll("[data-impact-button]").forEach((button) => {
    const isActive = button.dataset.impactButton === scenarioName;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  });
};

if (impactLab) {
  impactLab.querySelectorAll("[data-impact-button]").forEach((button) => {
    button.addEventListener("click", () => updateImpactScenario(button.dataset.impactButton));
  });
  updateImpactScenario(impactLab.dataset.impactScenario || "idle");
}

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

  document.querySelectorAll(".showcase-grid [data-reveal]").forEach((card, index) => {
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
