(() => {
	const rawLink = window.location.hash.slice(1);
	if (!rawLink) return;
	try {
		const link = new URL(rawLink);
		const loopback =
			link.hostname === "127.0.0.1" ||
			link.hostname === "localhost" ||
			link.hostname === "[::1]" ||
			link.hostname === "::1";
		if (!loopback || link.protocol !== "ws:" || !/^\/r\/[A-Za-z0-9_-]{10,64}\.[A-Za-z0-9_-]+$/.test(link.pathname)) return;
		link.protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
		link.hostname = window.location.hostname;
		link.port = window.location.port;
		history.replaceState(null, "", `${window.location.pathname}${window.location.search}#${link.href}`);
	} catch {
		// The guest client reports malformed collab links after it loads.
	}
})();
