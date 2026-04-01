import ./common
import ./implementations/archetype_ecs/runtime

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
  result.total = game.actors.len
  result.max = result.total
  for actor in game.actors.items:
    if actor.dead:
      inc result.dead
    else:
      case game.archetypeOf(actor.entity)
      of CameraArch:
        discard
      of PaddleArch:
        inc result.live
        inc result.paddle
      of BallArch:
        inc result.live
        inc result.ball
      of BrickArch:
        inc result.live
        inc result.brick
      of ParticleArch:
        inc result.live
        inc result.particle
      of TrailArch:
        inc result.live
        inc result.trail

when isMainModule:
  benchmarkMain(
    "archetype-ecs",
    initBenchGame,
    createScene,
    applyInput,
    update,
    snapshot
  )
