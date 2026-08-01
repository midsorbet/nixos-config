(() => {
	try {
		const saved = localStorage.getItem("omp-collab-theme");
		const system = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
		const theme = saved === "light" || saved === "dark" ? saved : system;
		document.documentElement.dataset.theme = theme;
		document.documentElement.style.colorScheme = theme;
	} catch {}
})();
