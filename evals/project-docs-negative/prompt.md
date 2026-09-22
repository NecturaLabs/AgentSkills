---
name: project-docs-negative
description: A request to explain the event stream in conversation, not to document it — one word away from the explicit case, and must not fire the skill.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

Explain how this event stream works. I'm looking at the notifications feed and I don't understand
how updates get from the server to the client — just walk me through the mechanism.

```js
// server/routes/notifications.js
router.get('/notifications/stream', requireUser, (req, res) => {
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
  res.flushHeaders();
  const unsubscribe = bus.subscribe(`user:${req.user.id}`, (event) => {
    res.write(`id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event.payload)}\n\n`);
  });
  const ping = setInterval(() => res.write(': ping\n\n'), 25000);
  req.on('close', () => { clearInterval(ping); unsubscribe(); });
});

// client/src/useNotifications.js
export function useNotifications(onEvent) {
  useEffect(() => {
    const source = new EventSource('/notifications/stream', { withCredentials: true });
    source.addEventListener('notification', (e) => onEvent(JSON.parse(e.data)));
    return () => source.close();
  }, [onEvent]);
}
```
