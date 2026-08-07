/// <reference types="vite/client" />
import React from 'react'
import ReactDOM from 'react-dom/client'
import { App } from './App'
import { TamerArenaDemo } from './tamerengine/TamerArenaDemo'
import { Arena3DPreview } from './tamerengine/three/Arena3DPreview'
import { validateDesign } from './validate'
import './styles.css'

if (import.meta.env.DEV) validateDesign()

// DEV ROUTE: `?tamerarena` opens the standalone tamerengine field-battle renderer,
// entirely outside the game/tournament flow — a test-branch preview of the new
// battle engine, not wired into the real loop.
// `?arena3d` opens the 3D battlefield PROTOTYPE, beside the 2D one rather than in
// place of it — it exists to be judged against the current renderer, not to replace it
// until it has won.
const Root = window.location.search.includes('arena3d') ? Arena3DPreview
  : window.location.search.includes('tamerarena') ? TamerArenaDemo : App

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>,
)
