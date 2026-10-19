import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './style.css';

class AppBoundary extends React.Component<{ children: React.ReactNode }, { error: string }> {
  state = { error: '' };
  static getDerivedStateFromError(error: Error) { return { error: error.message }; }
  render() {
    return this.state.error ? <main className="startup-error"><h1>Daevalog could not display this page.</h1><p>{this.state.error}</p><button onClick={() => location.reload()}>Reload companion</button></main> : this.props.children;
  }
}
createRoot(document.getElementById('root')!).render(<AppBoundary><App /></AppBoundary>);
if (import.meta.env.VITE_UI_SMOKE === '1') void import('./smoke').then(m => m.runSmoke());
