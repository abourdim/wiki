// Extra bit of the robot's web page (web_server js_include).
// Shows the camera stream (port 8080) at the top of the page.
// - The camera serves one viewer at a time, so the view can be switched off
//   to free it for another tablet or for VLC.
// - The camera can only flip/mirror (180°), so a module mounted sideways is
//   turned here, in the browser. The choice is remembered on this device.
(() => {
  const url = () => `http://${location.hostname}:8080/?t=${Date.now()}`;
  const KEY = "robot-cam-rotate";
  let rot = 270;                       // module on the robot is mounted sideways
  try { const v = localStorage.getItem(KEY); if (v !== null) rot = +v % 360; } catch (e) {}

  const box = document.createElement("div");
  box.style.cssText =
    "max-width:640px;margin:12px auto;padding:10px;border-radius:12px;" +
    "background:#1f2937;color:#fff;font-family:sans-serif;text-align:center";

  const title = document.createElement("div");
  title.textContent = "📷 Robot camera";
  title.style.cssText = "font-size:20px;font-weight:bold;margin-bottom:8px";

  // The frame keeps the picture's shape whichever way it is turned
  const frame = document.createElement("div");
  frame.style.cssText =
    "position:relative;margin:0 auto;overflow:hidden;border-radius:8px;background:#000";

  const img = document.createElement("img");
  img.alt = "camera";
  img.style.cssText = "position:absolute;top:50%;left:50%";

  const msg = document.createElement("div");
  msg.style.cssText = "margin:6px 0;color:#fbbf24;display:none";

  const btnCss =
    "margin:8px 4px 0;padding:8px 18px;font-size:16px;border:0;border-radius:8px;" +
    "background:#3b82f6;color:#fff;cursor:pointer";
  const btn = document.createElement("button");
  btn.style.cssText = btnCss;
  const rotBtn = document.createElement("button");
  rotBtn.style.cssText = btnCss;
  rotBtn.textContent = "🔄 Turn picture";

  const layout = () => {
    const side = rot % 180 !== 0;
    frame.style.width = side ? "min(100%, 360px)" : "100%";
    frame.style.aspectRatio = side ? "3 / 4" : "4 / 3";
    // sideways: the picture's width must match the frame's height (4/3 of its width)
    img.style.width = side ? "133.334%" : "100%";
    img.style.transform = `translate(-50%, -50%) rotate(${rot}deg)`;
  };

  let on = true;
  const show = () => {
    msg.style.display = "none";
    if (on) {
      img.src = url();
      frame.style.display = "";
      btn.textContent = "⏸️ Camera off";
    } else {
      img.removeAttribute("src");   // closes the stream for others
      frame.style.display = "none";
      btn.textContent = "▶️ Camera on";
    }
  };
  img.onerror = () => {
    if (!on || !img.getAttribute("src")) return;
    msg.textContent = "No picture: someone else may be watching. Retrying...";
    msg.style.display = "";
    setTimeout(() => on && (img.src = url()), 3000);
  };
  img.onload = () => (msg.style.display = "none");
  btn.onclick = () => { on = !on; show(); };
  rotBtn.onclick = () => {
    rot = (rot + 90) % 360;
    try { localStorage.setItem(KEY, rot); } catch (e) {}
    layout();
  };

  frame.append(img);
  box.append(title, frame, msg, btn, rotBtn);
  document.body.prepend(box);
  layout();
  show();
})();
