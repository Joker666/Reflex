const copyButton = document.querySelector("[data-copy]");

copyButton?.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(copyButton.dataset.copy);
    const label = copyButton.querySelector(".copy-label");
    label.textContent = "Copied";
    window.setTimeout(() => {
      label.textContent = "Copy";
    }, 1600);
  } catch {
    const range = document.createRange();
    range.selectNode(document.querySelector(".install-block code"));
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }
});
