import ./common
import ./implementations/pure_dod/runtime

type
  BenchGame = Game

proc initBenchGame(): BenchGame =
  result = BenchGame(
    isRunning: true,
    windowWidth: WindowWidth,
    windowHeight: WindowHeight,
    clearColor: [0'u8, 0, 0, 255]
  )

proc applyInput(game: var BenchGame; tick: int) =
  let phase = (tick div 30) mod 3
  game.inputState[Left] = phase == 0
  game.inputState[Right] = phase == 2

proc update(game: var BenchGame; timings: var Timings) =
  timeInto timings.controlBall:
    sysControlBall(game)
  timeInto timings.controlBrick:
    sysControlBrick(game)
  timeInto timings.controlPaddle:
    sysControlPaddle(game)
  timeInto timings.shake:
    sysShake(game)
  timeInto timings.fade:
    sysFade(game)
  timeInto timings.cleanupDead:
    cleanupDead(game)
  timeInto timings.move:
    sysMove(game)
  timeInto timings.transform2d:
    sysTransform2d(game)
  timeInto timings.collide:
    sysCollide(game)
  inc game.tickId

proc snapshot(game: BenchGame): Snapshot =
  result = Snapshot()
  result.total = ord(game.paddle.active) + game.balls.len + game.bricks.len +
    game.particles.len + game.trails.len
  result.max = result.total
  result.live = result.total
  if game.paddle.active:
    result.paddle = 1
  result.ball = game.balls.len
  result.brick = game.bricks.len
  result.particle = game.particles.len
  result.trail = game.trails.len

when isMainModule:
  benchmarkMain(
    "pure-dod",
    initBenchGame,
    createScene,
    applyInput,
    update,
    snapshot
  )
