import ./common
import ./implementations/entity_component/runtime

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
  result.total = game.entities.len - 1
  result.max = result.total
  for entity in game.entities.items:
    if entity.alive:
      case entity.kind
      of CameraKind:
        discard
      of PaddleKind:
        inc result.live
        inc result.paddle
      of BallKind:
        inc result.live
        inc result.ball
      of BrickKind:
        inc result.live
        inc result.brick
      of ParticleKind:
        inc result.live
        inc result.particle
      of TrailKind:
        inc result.live
        inc result.trail

when isMainModule:
  benchmarkMain(
    "entity-component",
    initBenchGame,
    createScene,
    applyInput,
    update,
    snapshot
  )
