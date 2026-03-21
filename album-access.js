(function () {
    const locks = window.ALBUM_LOCKS || {};
    const currentPage = window.location.pathname.split("/").pop() || "index.html";

    const getLock = (page) => {
        const entry = locks[page];
        if (!entry) {
            return null;
        }
        if (!entry.hash && !entry.code) {
            return null;
        }
        return entry;
    };

    const getDisplayTitle = (lock, page, fallbackTitle = "") => {
        if (lock && lock.title && lock.title !== page) {
            return lock.title;
        }
        if (fallbackTitle && fallbackTitle !== page) {
            return fallbackTitle;
        }
        return page;
    };

    const getPendingKey = (page) => `album-pending-unlock:${page}`;
    const hasPendingUnlock = (page) => window.sessionStorage.getItem(getPendingKey(page)) === "true";
    const setPendingUnlock = (page) => window.sessionStorage.setItem(getPendingKey(page), "true");
    const clearPendingUnlock = (page) => window.sessionStorage.removeItem(getPendingKey(page));
    const placeholderPixel = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==";

    const style = document.createElement("style");
    style.textContent = `
        .card.card-locked {
            position: relative;
        }

        .card-lock-media {
            position: relative;
            display: block;
        }

        .card-lock-media::after {
            content: "";
            position: absolute;
            inset: 0;
            border-radius: 5px;
            background: rgba(255, 255, 255, 0.82);
            pointer-events: none;
            z-index: 1;
        }

        .card.card-locked .card-lock-media img {
            filter: grayscale(0.3) blur(3.5px);
        }

        .card-lock-overlay {
            position: absolute;
            inset: 0;
            z-index: 4;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 14px;
            padding: 16px;
            pointer-events: none;
        }

        .card-lock-icon {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 72px;
            height: 72px;
            border-radius: 12px;
            background-color: rgba(255, 255, 255, 0.82);
            color: #111111;
            font-size: 38px;
            box-shadow: 0 6px 18px rgba(0, 0, 0, 0.05);
            backdrop-filter: blur(8px);
        }

        .card-lock-icon svg {
            width: 34px;
            height: 34px;
            display: block;
            fill: #111111;
        }

        .card.card-locked .card-lock-button {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: fit-content;
            padding: 10px 14px;
            border-radius: 12px;
            background-color: rgba(255, 255, 255, 0.72);
            color: #111111;
            font-size: 14px;
            font-weight: bold;
            box-shadow: 0 6px 18px rgba(0, 0, 0, 0.05);
            backdrop-filter: blur(8px);
            pointer-events: auto;
            transition: transform 0.3s ease, background-color 0.3s ease, color 0.3s ease;
        }

        .card.card-locked .card-lock-button:hover {
            background-color: #CBA135;
            color: #111111;
            transform: scale(1.025);
        }

        .album-lock-overlay {
            position: fixed;
            inset: 0;
            z-index: 3000;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            background-color: rgba(0, 0, 0, 0.78);
        }

        body.album-page-locked .container,
        body.album-page-locked .main-footer {
            visibility: hidden;
        }

        .album-lock-panel {
            width: min(100%, 420px);
            padding: 28px;
            border-radius: 22px;
            background-color: #ffffff;
            box-shadow: 0 18px 50px rgba(0, 0, 0, 0.18);
        }

        .album-lock-panel h2 {
            margin: 0 0 10px;
            font-size: 28px;
            text-align: left;
        }

        .album-lock-panel p {
            margin: 0 0 16px;
            line-height: 1.6;
            text-align: left;
        }

        .album-lock-panel input {
            width: 100%;
            padding: 14px 16px;
            border: 1px solid rgba(17, 17, 17, 0.14);
            border-radius: 14px;
            font: inherit;
            margin-bottom: 12px;
        }

        .album-lock-panel input:focus {
            outline: 2px solid rgba(203, 161, 53, 0.35);
            border-color: rgba(203, 161, 53, 0.65);
        }

        .album-lock-panel__error {
            min-height: 22px;
            margin-bottom: 10px;
            color: #a22d2d;
            font-size: 14px;
        }

        .album-lock-panel__actions {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }

        .album-lock-button {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            min-height: 46px;
            padding: 12px 18px;
            border: none;
            border-radius: 14px;
            font: inherit;
            font-weight: bold;
            cursor: pointer;
        }

        .album-lock-button--primary {
            background-color: #111111;
            color: #ffffff;
        }

        .album-lock-button--secondary {
            background-color: rgba(17, 17, 17, 0.08);
            color: #111111;
        }

        body.album-lock-open {
            overflow: hidden;
        }

        @media (max-width: 700px) {
            .card-lock-icon {
                width: 66px;
                height: 66px;
                font-size: 34px;
            }

            .card-lock-icon svg {
                width: 30px;
                height: 30px;
            }

            .card.card-locked .card-lock-button {
                padding: 8px 12px;
                font-size: 13px;
            }
        }
    `;
    document.head.appendChild(style);

    const sha256 = async (value) => {
        if (!window.crypto || !window.crypto.subtle) {
            throw new Error("Je browser ondersteunt geen veilige hashcontrole voor vergrendelde albums.");
        }
        const buffer = await window.crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
        return Array.from(new Uint8Array(buffer))
            .map((byte) => byte.toString(16).padStart(2, "0"))
            .join("");
    };

    const verifyCode = async (lock, inputValue) => {
        if (lock.hash) {
            const combined = `${lock.salt || ""}:${inputValue}`;
            const hashed = await sha256(combined);
            return hashed === lock.hash;
        }
        return inputValue === lock.code;
    };

    const decodeAlbumPath = (encodedValue) => {
        try {
            return window.atob(encodedValue);
        } catch {
            return "";
        }
    };

    const revealProtectedImages = () => {
        document.querySelectorAll(".photo-grid img[data-encoded-src]").forEach((image) => {
            const encodedValue = image.getAttribute("data-encoded-src");
            const decodedValue = decodeAlbumPath(encodedValue || "");
            if (decodedValue) {
                image.src = decodedValue;
            }
        });
    };

    const createPrompt = ({ title, hint, onSubmit, secondaryAction }) => {
        const overlay = document.createElement("div");
        overlay.className = "album-lock-overlay";

        const panel = document.createElement("div");
        panel.className = "album-lock-panel";

        const heading = document.createElement("h2");
        heading.textContent = "Album vergrendeld";

        const text = document.createElement("p");
        text.textContent = `${title} is beveiligd met een toegangscode.`;

        const hintText = document.createElement("p");
        hintText.textContent = hint || "Voer de code in om dit album te openen.";

        const input = document.createElement("input");
        input.type = "password";
        input.placeholder = "Toegangscode";
        input.autocomplete = "off";

        const error = document.createElement("div");
        error.className = "album-lock-panel__error";

        const actions = document.createElement("div");
        actions.className = "album-lock-panel__actions";

        const submitButton = document.createElement("button");
        submitButton.type = "button";
        submitButton.className = "album-lock-button album-lock-button--primary";
        submitButton.textContent = "Open album";

        const secondaryButton = document.createElement("button");
        secondaryButton.type = "button";
        secondaryButton.className = "album-lock-button album-lock-button--secondary";
        secondaryButton.textContent = secondaryAction ? secondaryAction.label : "Annuleren";

        const closePrompt = () => {
            overlay.remove();
            document.body.classList.remove("album-lock-open");
        };

        const submit = async () => {
            try {
                const success = await onSubmit(input.value);
                if (success) {
                    closePrompt();
                } else {
                    error.textContent = "De code klopt niet.";
                    input.select();
                }
            } catch (promptError) {
                error.textContent = promptError.message || "Controle van de code is mislukt.";
            }
        };

        submitButton.addEventListener("click", submit);
        input.addEventListener("keydown", (event) => {
            if (event.key === "Enter") {
                event.preventDefault();
                submit();
            }
        });

        secondaryButton.addEventListener("click", () => {
            if (secondaryAction && secondaryAction.onClick) {
                secondaryAction.onClick();
            }
            closePrompt();
        });

        actions.append(submitButton, secondaryButton);
        panel.append(heading, text, hintText, input, error, actions);
        overlay.appendChild(panel);
        document.body.appendChild(overlay);
        document.body.classList.add("album-lock-open");
        window.setTimeout(() => input.focus(), 30);
    };

    const attachLocksToAlbumGrid = () => {
        const albumCards = Array.from(document.querySelectorAll(".grid .card"));

        albumCards.forEach((card) => {
            const mediaAnchor = card.querySelector("a[href$='.html']");
            if (!mediaAnchor) {
                return;
            }

            const targetPage = mediaAnchor.getAttribute("href");
            const lock = getLock(targetPage);
            if (!lock) {
                return;
            }

            const title = getDisplayTitle(lock, targetPage, card.querySelector("h2")?.textContent || "");
            card.classList.add("card-locked");
            mediaAnchor.classList.add("card-lock-media");

            const overlay = document.createElement("div");
            overlay.className = "card-lock-overlay";

            const icon = document.createElement("div");
            icon.className = "card-lock-icon";
            icon.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17 9h-1V7a4 4 0 0 0-8 0v2H7a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8a2 2 0 0 0-2-2Zm-6 7.73V17a1 1 0 1 0 2 0v-.27a2 2 0 1 0-2 0ZM10 9V7a2 2 0 1 1 4 0v2h-4Z"/></svg>';

            const button = document.createElement("button");
            button.type = "button";
            button.className = "card-lock-button";
            button.textContent = "Ontgrendel album";

            button.addEventListener("click", () => {
                createPrompt({
                    title,
                    hint: lock.hint,
                    onSubmit: async (value) => {
                        const success = await verifyCode(lock, value);
                        if (success) {
                            setPendingUnlock(targetPage);
                            window.location.href = targetPage;
                        }
                        return success;
                    },
                });
            });

            overlay.append(icon, button);
            mediaAnchor.appendChild(overlay);
        });
    };

    const guardAlbumPage = () => {
        const lock = getLock(currentPage);
        if (!lock) {
            revealProtectedImages();
            return;
        }

        if (hasPendingUnlock(currentPage)) {
            clearPendingUnlock(currentPage);
            revealProtectedImages();
            return;
        }

        document.body.classList.add("album-page-locked");

        const title = getDisplayTitle(lock, currentPage, document.querySelector(".page-header h1")?.textContent || "");
        createPrompt({
            title,
            hint: lock.hint,
            onSubmit: async (value) => {
                const success = await verifyCode(lock, value);
                if (success) {
                    document.body.classList.remove("album-page-locked");
                    revealProtectedImages();
                }
                return success;
            },
            secondaryAction: {
                label: "Terug naar albums",
                onClick: () => {
                    window.location.href = "albums.html";
                },
            },
        });
    };

    if (document.querySelector(".grid")) {
        attachLocksToAlbumGrid();
    }

    if (document.querySelector(".photo-grid")) {
        guardAlbumPage();
    }
})();
