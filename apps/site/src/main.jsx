import React, { useEffect } from "react";
import { createRoot } from "react-dom/client";
import "./base.css";
import { Header, useRoute, Footer } from "./shared";
import Gallery from "./Gallery";
import Terminal from "./Terminal";
import Editorial from "./Editorial";
import { chapters } from "./stories";
import "./edition.css";
import "./desk.css";
import "./chapter-reading.css";
function App() {
  const route = useRoute(),
    path = route.split(/[?#]/)[0],
    home = path === "/",
    desk = path.startsWith("/terminal");
  const View = desk ? Terminal : Editorial;
  const previousPath = React.useRef(null);
  useEffect(() => {
    const title =
      chapters.find((c) => c.href === path)?.name ||
      (desk
        ? "Paper terminal"
        : path
            .split("/")
            .filter(Boolean)
            .at(-1)
            ?.replaceAll("-", " ")
            .replace(/^./, (s) => s.toUpperCase()));
    document.title = import.meta.env.DEV
      ? "LIVE preview"
      : home
        ? "Closari · Stock-close markets"
        : title + " · Closari";
    const target = location.hash
      ? document.getElementById(location.hash.slice(1))
      : null;
    if (target) requestAnimationFrame(() => target.scrollIntoView());
    else if (!desk || previousPath.current !== path) window.scrollTo(0, 0);
    previousPath.current = path;
  }, [route]);
  return (
    <>
      <Header route={route} />
      {home ? <Gallery /> : <View route={route} />}
      {!home && !desk && <Footer />}
    </>
  );
}
createRoot(document.getElementById("root")).render(<App />);
