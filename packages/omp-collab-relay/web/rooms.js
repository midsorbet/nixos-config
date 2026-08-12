const root = document.getElementById("root");

function relativeTime(value) {
	const seconds = Math.max(
		0,
		Math.floor((Date.now() - new Date(value).getTime()) / 1000),
	);
	if (seconds < 60) return "just now";
	const minutes = Math.floor(seconds / 60);
	if (minutes < 60) return `${minutes}m ago`;
	return `${Math.floor(minutes / 60)}h ago`;
}

function openRoom(link) {
	history.replaceState(null, "", link);
	window.location.reload();
}

function roomCard(room) {
	const card = document.createElement("button");
	card.className = "rooms-card";
	card.type = "button";
	card.addEventListener("click", () => openRoom(room.link));

	const status = document.createElement("span");
	status.className = "rooms-status";
	status.textContent = "live";

	const title = document.createElement("strong");
	title.textContent = room.label;

	const cwd = document.createElement("span");
	cwd.className = "rooms-cwd";
	cwd.textContent = room.cwd || "working directory unavailable";

	const meta = document.createElement("span");
	meta.className = "rooms-meta";
	meta.textContent = `${room.guests ? "viewing now" : "ready to join"} · active ${relativeTime(room.lastActivityAt)}`;

	const arrow = document.createElement("span");
	arrow.className = "rooms-arrow";
	arrow.textContent = "Open →";

	card.append(status, title, cwd, meta, arrow);
	return card;
}

async function refreshRooms() {
	const list = document.querySelector(".rooms-list");
	const count = document.querySelector(".rooms-count");
	try {
		const response = await fetch("/api/rooms", { cache: "no-store" });
		if (!response.ok)
			throw new Error(`room directory returned ${response.status}`);
		const rooms = await response.json();
		count.textContent = `${rooms.length} active ${rooms.length === 1 ? "room" : "rooms"}`;
		list.replaceChildren();
		if (rooms.length === 0) {
			const empty = document.createElement("div");
			empty.className = "rooms-empty";
			empty.innerHTML =
				"<strong>No active sessions</strong><span>Run <code>/remote-collab view</code> in an OMP session.</span>";
			list.append(empty);
			return;
		}
		for (const room of rooms) list.append(roomCard(room));
	} catch (error) {
		count.textContent = "directory unavailable";
		list.replaceChildren();
		const failure = document.createElement("div");
		failure.className = "rooms-empty rooms-error";
		failure.textContent =
			error instanceof Error ? error.message : String(error);
		list.append(failure);
	}
}

root.innerHTML = `
	<main class="rooms-shell">
		<header class="rooms-header">
			<div class="rooms-brand"><span class="rooms-mark"></span><span class="rooms-pi">π</span> omp collab</div>
			<div>
				<p class="rooms-eyebrow">REMOTE WORKSPACE</p>
				<h1>Choose a live session</h1>
				<p class="rooms-subtitle">Each room is a separate OMP agent session running on the Mini.</p>
			</div>
			<div class="rooms-toolbar">
				<span class="rooms-count" aria-live="polite">loading rooms…</span>
				<button class="rooms-refresh" type="button">Refresh</button>
			</div>
		</header>
		<section class="rooms-list" aria-label="Active OMP sessions"></section>
	</main>`;

document
	.querySelector(".rooms-refresh")
	.addEventListener("click", refreshRooms);
await refreshRooms();
setInterval(refreshRooms, 5000);
