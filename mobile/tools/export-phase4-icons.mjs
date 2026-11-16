// Export only newly needed icons from the installed, read-only React reference.
import { writeFile } from 'node:fs/promises';
for (const name of ['graduation-cap', 'log-out', 'file-up', 'badge-check', 'clock']) {
  const { __iconData } = await import(`file:///D:/UI%20AI%20Review/node_modules/lucide-react/dist/esm/icons/${name}.mjs`);
  const content = __iconData.node.map(([tag, attrs]) => `<${tag} ${Object.entries(attrs).filter(([key]) => key !== 'key').map(([key, value]) => `${key}="${value}"`).join(' ')}/>`).join('');
  await writeFile(`assets/icons/${name}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">${content}</svg>`);
}
