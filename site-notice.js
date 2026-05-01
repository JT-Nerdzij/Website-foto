(() => {
    const STORAGE_KEY = "nmf:site-notice-dismissed:v1";

    const isDismissed = () => {
        try {
            return window.localStorage.getItem(STORAGE_KEY) === "true";
        } catch {
            return false;
        }
    };

    const setDismissed = () => {
        try {
            window.localStorage.setItem(STORAGE_KEY, "true");
        } catch {
            // ignore
        }
    };

    const createNotice = () => {
        const wrap = document.createElement("div");
        wrap.className = "site-notice-wrap";

        const notice = document.createElement("div");
        notice.className = "site-notice";
        notice.setAttribute("role", "status");
        notice.setAttribute("aria-live", "polite");

        const text = document.createElement("div");
        text.className = "site-notice__text";
        text.textContent =
            "Er wordt op het moment nog gewerkt aan de site, hierdoor kn de site sloom zijn.";

        const close = document.createElement("button");
        close.type = "button";
        close.className = "site-notice__close";
        close.setAttribute("aria-label", "Melding sluiten");
        close.textContent = "×";

        close.addEventListener("click", () => {
            setDismissed();
            wrap.remove();
        });

        notice.append(text, close);
        wrap.appendChild(notice);
        return wrap;
    };

    const mount = () => {
        if (isDismissed()) {
            return;
        }

        if (document.querySelector(".site-notice-wrap")) {
            return;
        }

        const header = document.querySelector("header");
        const target = header || document.body.firstElementChild;
        if (!target) {
            return;
        }

        const notice = createNotice();

        if (header) {
            header.insertAdjacentElement("afterend", notice);
        } else {
            document.body.insertAdjacentElement("afterbegin", notice);
        }
    };

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", mount);
    } else {
        mount();
    }
})();
