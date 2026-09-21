// ==========================================================================
// Reflex Landing Page Interactive Logic
// ==========================================================================

function init() {
  // Elements
  const announcer = document.getElementById("sr-announcer");
  const copyButton = document.querySelector(".btn-copy");
  const chooserPanel = document.getElementById("chooser-panel");
  const chooserRows = document.querySelectorAll(".chooser-row");
  const scenarioChips = document.querySelectorAll(".scenario-chip:not(.chip-override)");
  const overrideToggle = document.getElementById("btn-override-toggle");
  const statusMsg = document.querySelector(".status-msg");
  const launchToast = document.getElementById("launch-toast");
  const toastText = launchToast?.querySelector(".toast-text");
  const settingsBtn = document.getElementById("btn-settings");
  const settingsModal = document.getElementById("settings-modal");
  const closeModalBtn = document.getElementById("btn-close-modal");
  const saveModalBtn = document.getElementById("btn-save-modal");
  const clockDisplay = document.getElementById("desktop-clock");

  let currentSelectedIndex = 1;
  let copyTimeoutId = null;
  let toastTimeoutId = null;
  let isOptionHeld = false;

  // Screen reader announcer helper
  function announce(text) {
    if (announcer) {
      announcer.textContent = "";
      window.setTimeout(() => {
        announcer.textContent = text;
      }, 50);
    }
  }

  // Live macOS Clock in Simulated Menubar
  function updateClock() {
    if (!clockDisplay) return;
    const now = new Date();
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    const day = days[now.getDay()];
    let hours = now.getHours();
    const minutes = String(now.getMinutes()).padStart(2, "0");
    const ampm = hours >= 12 ? "PM" : "AM";
    hours = hours % 12 || 12;
    clockDisplay.textContent = `${day} ${hours}:${minutes} ${ampm}`;
  }
  updateClock();
  setInterval(updateClock, 30000);

  // --------------------------------------------------------------------------
  // 1. Copy Command to Clipboard
  // --------------------------------------------------------------------------
  copyButton?.addEventListener("click", async () => {
    const textToCopy = copyButton.dataset.copy || "";
    const copyLabel = copyButton.querySelector(".copy-text");
    let succeeded = false;

    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(textToCopy);
        succeeded = true;
      } else {
        throw new Error("Clipboard API unavailable");
      }
    } catch {
      const codeEl = document.querySelector(".brew-pill code");
      if (codeEl) {
        const range = document.createRange();
        range.selectNodeContents(codeEl);
        const selection = window.getSelection();
        selection?.removeAllRanges();
        selection?.addRange(range);
        try {
          succeeded = document.execCommand("copy");
        } catch {
          succeeded = false;
        }
      }
    }

    if (succeeded && copyLabel) {
      if (copyTimeoutId) clearTimeout(copyTimeoutId);
      copyLabel.textContent = "Copied";
      copyButton.classList.add("copied");
      copyButton.setAttribute("aria-label", "Copied Homebrew command to clipboard");
      announce("Copied Homebrew command to clipboard");

      copyTimeoutId = window.setTimeout(() => {
        copyLabel.textContent = "Copy";
        copyButton.classList.remove("copied");
        copyButton.setAttribute("aria-label", "Copy Homebrew command");
        copyTimeoutId = null;
      }, 2000);
    }
  });

  // --------------------------------------------------------------------------
  // 2. Reflex Chooser Target Selection & Simulated Launch
  // --------------------------------------------------------------------------
  function selectTarget(index, options = { showToast: false, isAI: false, confidence: 95 }) {
    const clamped = Math.max(1, Math.min(6, index));
    currentSelectedIndex = clamped;

    chooserRows.forEach((row) => {
      const rowIndex = parseInt(row.dataset.index, 10);
      const isMatch = rowIndex === clamped;
      row.classList.toggle("is-selected", isMatch);
      row.setAttribute("aria-selected", isMatch ? "true" : "false");

      // Manage sparkle icon for AI suggestion
      const sparkle = row.querySelector(".target-sparkle");
      if (sparkle) {
        sparkle.remove();
      }
      if (isMatch && options.isAI) {
        const info = row.querySelector(".target-info");
        if (info) {
          const newSparkle = document.createElement("span");
          newSparkle.className = "target-sparkle";
          newSparkle.setAttribute("aria-hidden", "true");
          newSparkle.textContent = "✦";
          info.appendChild(newSparkle);
        }
      }
    });

    const activeRow = document.querySelector(`.chooser-row[data-index="${clamped}"]`);
    const targetName = activeRow?.dataset.name || "Browser";

    // Update status text
    if (statusMsg) {
      if (isOptionHeld) {
        statusMsg.textContent = "⌥ Option held: Manual choice mode";
        statusMsg.classList.remove("flash-active");
      } else if (options.isAI) {
        statusMsg.textContent = `⚡ Suggested ${targetName} • ${options.confidence}% confidence`;
        statusMsg.classList.add("flash-active");
      } else {
        statusMsg.textContent = `Automatic selection is active`;
        statusMsg.classList.remove("flash-active");
      }
    }

    // Trigger simulated launch toast if requested
    if (options.showToast && launchToast && toastText) {
      if (toastTimeoutId) clearTimeout(toastTimeoutId);
      toastText.textContent = `Opening link in ${targetName}...`;
      launchToast.classList.add("is-visible");
      announce(`Opening link in ${targetName}`);

      toastTimeoutId = window.setTimeout(() => {
        launchToast.classList.remove("is-visible");
        toastTimeoutId = null;
      }, 1800);
    }
  }

  // Row click event
  chooserRows.forEach((row) => {
    row.addEventListener("click", () => {
      const idx = parseInt(row.dataset.index, 10);
      selectTarget(idx, { showToast: true, isAI: false });
    });
  });

  // --------------------------------------------------------------------------
  // 3. Scenario Chips (Simulating Link Ingestion)
  // --------------------------------------------------------------------------
  const scenarios = {
    dia: { index: 1, name: "Dia", confidence: 99, reason: "Research paper" },
    chrome: { index: 3, name: "Google Chrome", confidence: 98, reason: "GitHub pull request" },
    comet: { index: 2, name: "Comet", confidence: 96, reason: "Linear issue" },
    helium: { index: 4, name: "Helium", confidence: 95, reason: "Swift documentation" },
    edge: { index: 5, name: "Microsoft Edge", confidence: 97, reason: "Azure client portal" },
    phi: { index: 6, name: "Phi", confidence: 92, reason: "Hacker News reader" },
  };

  scenarioChips.forEach((chip) => {
    chip.addEventListener("click", () => {
      const scenarioKey = chip.dataset.scenario;
      const data = scenarios[scenarioKey];
      if (!data) return;

      scenarioChips.forEach((c) => {
        c.classList.remove("is-active");
        c.setAttribute("aria-pressed", "false");
      });
      chip.classList.add("is-active");
      chip.setAttribute("aria-pressed", "true");

      // Animate AI routing decision
      if (statusMsg) {
        statusMsg.textContent = "⚡ Evaluating incoming link...";
      }

      window.setTimeout(() => {
        selectTarget(data.index, { showToast: false, isAI: true, confidence: data.confidence });
        announce(`Reflex routed to ${data.name} with ${data.confidence}% confidence for ${data.reason}`);
      }, 160);
    });
  });

  // Option Modifier Toggle button in scenarios bar
  overrideToggle?.addEventListener("click", () => {
    isOptionHeld = !isOptionHeld;
    overrideToggle.classList.toggle("is-active", isOptionHeld);
    overrideToggle.setAttribute("aria-pressed", isOptionHeld ? "true" : "false");
    
    if (isOptionHeld) {
      if (statusMsg) statusMsg.textContent = "⌥ Option held: Manual choice mode";
      announce("Option modifier active: automatic routing bypassed");
    } else {
      selectTarget(currentSelectedIndex, { isAI: false });
    }
  });

  // --------------------------------------------------------------------------
  // 4. Global Keyboard Shortcuts
  // --------------------------------------------------------------------------
  window.addEventListener("keydown", (e) => {
    // If inside an open modal or input, don't hijack keys
    if (settingsModal?.classList.contains("is-open")) {
      if (e.key === "Escape") closeModal();
      return;
    }

    // Number keys 1-6
    if (e.key >= "1" && e.key <= "6" && !e.metaKey && !e.ctrlKey) {
      const num = parseInt(e.key, 10);
      selectTarget(num, { showToast: true, isAI: false });
      return;
    }

    // Arrow keys navigation
    if (e.key === "ArrowDown") {
      e.preventDefault();
      const next = currentSelectedIndex >= 6 ? 1 : currentSelectedIndex + 1;
      selectTarget(next, { showToast: false, isAI: false });
      return;
    }

    if (e.key === "ArrowUp") {
      e.preventDefault();
      const prev = currentSelectedIndex <= 1 ? 6 : currentSelectedIndex - 1;
      selectTarget(prev, { showToast: false, isAI: false });
      return;
    }

    // Return to confirm
    if (e.key === "Enter" && document.activeElement === chooserPanel) {
      e.preventDefault();
      selectTarget(currentSelectedIndex, { showToast: true, isAI: false });
      return;
    }

    // Alt/Option key tracking
    if (e.key === "Alt" && !isOptionHeld) {
      isOptionHeld = true;
      overrideToggle?.classList.add("is-active");
      overrideToggle?.setAttribute("aria-pressed", "true");
      if (statusMsg) statusMsg.textContent = "⌥ Option held: Manual choice mode";
    }
  });

  window.addEventListener("keyup", (e) => {
    if (e.key === "Alt") {
      isOptionHeld = false;
      overrideToggle?.classList.remove("is-active");
      overrideToggle?.setAttribute("aria-pressed", "false");
      selectTarget(currentSelectedIndex, { isAI: false });
    }
  });

  // --------------------------------------------------------------------------
  // 5. Settings Modal Interactive Toggle
  // --------------------------------------------------------------------------
  function openModal() {
    if (!settingsModal) return;
    settingsModal.classList.add("is-open");
    settingsModal.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    closeModalBtn?.focus();
    announce("Reflex settings dialog opened");
  }

  function closeModal() {
    if (!settingsModal) return;
    settingsModal.classList.remove("is-open");
    settingsModal.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    settingsBtn?.focus();
    announce("Settings closed");
  }

  settingsBtn?.addEventListener("click", openModal);
  closeModalBtn?.addEventListener("click", closeModal);
  saveModalBtn?.addEventListener("click", closeModal);

  settingsModal?.addEventListener("click", (e) => {
    if (e.target === settingsModal) {
      closeModal();
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
