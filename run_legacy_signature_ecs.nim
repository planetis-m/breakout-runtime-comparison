import ./common
import ./implementations/signature_query_ecs/runtime

type
  BenchGame = Game

proc initBenchGame(): BenchGame =
  let world = initWorld()
  result = BenchGame(
    world: world,
    camera: InvalidId,
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
    cleanup(game)
  timeInto timings.move:
    sysMove(game)
  timeInto timings.transform2d:
    sysTransform2d(game)
  timeInto timings.collide:
    sysCollide(game)
  inc game.tickId

proc countTransformOnly(game: BenchGame): int =
  result = 0
  for _, signature in game.world.signature.pairs:
    if HasTransform2d in signature and HasHierarchy in signature and
        HasDraw2d notin signature and HasCollide notin signature and
        HasFade notin signature and HasMove notin signature and
        HasControlBall notin signature and HasControlBrick notin signature and
        HasControlPaddle notin signature:
      inc result

proc snapshot(game: BenchGame): Snapshot =
  result = Snapshot()
  let transformOnly = game.countTransformOnly()
  result.live = game.world.signature.len - transformOnly
  result.total = game.world.signature.len - transformOnly
  result.max = result.total
  for _, signature in game.world.signature.pairs:
    if HasControlPaddle in signature:
      inc result.paddle
    if HasControlBall in signature:
      inc result.ball
    if HasControlBrick in signature:
      inc result.brick
    if HasFade in signature and HasMove in signature and HasControlBall notin signature and
        HasControlPaddle notin signature and HasControlBrick notin signature and HasCollide notin signature:
      inc result.particle
    elif HasFade in signature and HasDraw2d in signature and HasMove notin signature and
        HasControlBall notin signature and HasControlPaddle notin signature and HasControlBrick notin signature:
      inc result.trail

when isMainModule:
  benchmarkMain(
    "signature-query-ecs",
    initBenchGame,
    createScene,
    applyInput,
    update,
    snapshot
  )
