import { GameApp } from './app/GameApp';
import './styles/main.css';

const root = document.querySelector<HTMLElement>('#app');
if (!root) throw new Error('Missing #app root.');

const app = new GameApp(root);
void app.boot();

if (import.meta.hot) {
  import.meta.hot.dispose(() => app.destroy());
}
