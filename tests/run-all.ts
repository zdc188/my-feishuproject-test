import { runAll } from './harness';
import './engine.test';
import './input.test';
import './player.test';
import './collision.test';
import './map.test';
import './mapdata.test';
import './resource-state.test';

runAll().then((failed) => {
  if (failed > 0) {
    process.exitCode = 1;
  }
});
