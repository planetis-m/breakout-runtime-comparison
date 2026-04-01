import std/math
import ../../bench_random
import ../../bench_sizes
import ../../shared/[headless_raylib, vmath]

type
  Input* = enum
    Right, Left

  CollisionFlag* = enum
    Hit

  TransformFlag* = enum
    Dirty, Fresh, HasPrevious

  NodeIdx* = distinct int32

  Collision* = object
    flags*: set[CollisionFlag]
    hit*: Vec2

  Hierarchy* = object
    head*: NodeIdx
    prev*: NodeIdx
    next*: NodeIdx
    parent*: NodeIdx

  Collide* = object
    size*: Vec2
    min*, max*: Point2
    center*: Point2
    collision*: Collision

  Draw2d* = object
    width*, height*: int32
    color*: array[4, uint8]

  Fade* = object
    step*: float32

  Move* = object
    direction*: Vec2
    speed*: float32

  Previous* = object
    position*: Point2
    rotation*: Rad
    scale*: Vec2

  Transform2d* = object
    world*: Mat2d
    translation*: Vec2
    rotation*: Rad
    scale*: Vec2
    flags*: set[TransformFlag]

  Shake* = object
    duration*: float32
    strength*: float32

  TransformNode = object
    transform*: Transform2d
    hierarchy*: Hierarchy
    previous*: Previous
    active*: bool

  Camera* = object
    node*: NodeIdx
    shake*: Shake

  Paddle* = object
    active*: bool
    node*: NodeIdx
    collide*: Collide
    draw*: Draw2d
    move*: Move

  Ball* = object
    node*: NodeIdx
    collide*: Collide
    draw*: Draw2d
    move*: Move

  Brick* = object
    node*: NodeIdx
    collide*: Collide
    draw*: Draw2d
    fade*: Fade
    dead*: bool

  Particle* = object
    node*: NodeIdx
    draw*: Draw2d
    fade*: Fade
    move*: Move
    dead*: bool

  Trail* = object
    node*: NodeIdx
    draw*: Draw2d
    fade*: Fade
    dead*: bool

  Game* = object
    camera*: Camera
    paddle*: Paddle
    balls*: seq[Ball]
    bricks*: seq[Brick]
    particles*: seq[Particle]
    trails*: seq[Trail]

    nodes*: seq[TransformNode]
    freeNodes*: seq[int32]

    inputState*: array[Input, bool]
    clearColor*: array[4, uint8]

    isRunning*: bool
    windowWidth*, windowHeight*: int32
    tickId*: int

    raylib*: RaylibContext

const
  NoNodeIdx* = NodeIdx(-1'i32)

proc `==`*(a, b: NodeIdx): bool {.borrow.}

func intersects*[K: enum](a, b: set[K]): bool {.inline.} =
  (a * b) != {}

proc initTransformNode(translation: Vec2): TransformNode =
  TransformNode(
    transform: Transform2d(
      world: mat2d(),
      translation: translation,
      rotation: 0.Rad,
      scale: vec2(1, 1),
      flags: {Dirty, Fresh}
    ),
    hierarchy: Hierarchy(
      head: NoNodeIdx,
      prev: NoNodeIdx,
      next: NoNodeIdx,
      parent: NoNodeIdx
    ),
    previous: Previous(
      position: point2(0, 0),
      rotation: 0.Rad,
      scale: vec2(1, 1)
    ),
    active: true
  )

proc parent(game: Game; idx: NodeIdx): NodeIdx =
  game.nodes[idx.int].hierarchy.parent

proc firstChild(game: Game; idx: NodeIdx): NodeIdx =
  game.nodes[idx.int].hierarchy.head

proc nextSibling(game: Game; idx: NodeIdx): NodeIdx =
  game.nodes[idx.int].hierarchy.next

proc prependChild(game: var Game; parent, child: NodeIdx) =
  let head = game.nodes[parent.int].hierarchy.head

  game.nodes[child.int].hierarchy.parent = parent
  game.nodes[child.int].hierarchy.prev = NoNodeIdx
  game.nodes[child.int].hierarchy.next = head
  if head != NoNodeIdx:
    game.nodes[head.int].hierarchy.prev = child
  game.nodes[parent.int].hierarchy.head = child

proc removeNode(game: var Game; node: NodeIdx) =
  let parent = game.nodes[node.int].hierarchy.parent
  let prev = game.nodes[node.int].hierarchy.prev
  let next = game.nodes[node.int].hierarchy.next
  let head = game.nodes[node.int].hierarchy.head

  if parent != NoNodeIdx and game.nodes[parent.int].hierarchy.head == node:
    game.nodes[parent.int].hierarchy.head = next
  if prev != NoNodeIdx:
    game.nodes[prev.int].hierarchy.next = next
  if next != NoNodeIdx:
    game.nodes[next.int].hierarchy.prev = prev

  game.nodes[node.int].hierarchy = Hierarchy(
    head: head,
    prev: NoNodeIdx,
    next: NoNodeIdx,
    parent: NoNodeIdx
  )

proc allocNode(game: var Game; translation: Vec2; parent = NoNodeIdx): NodeIdx =
  if game.freeNodes.len > 0:
    result = NodeIdx(game.freeNodes.pop())
    game.nodes[result.int] = initTransformNode(translation)
  else:
    result = NodeIdx(game.nodes.len.int32)
    game.nodes.add(initTransformNode(translation))

  if parent != NoNodeIdx:
    game.prependChild(parent, result)

proc freeNode(game: var Game; idx: NodeIdx) =
  if idx == NoNodeIdx:
    return
  game.removeNode(idx)
  game.nodes[idx.int].active = false
  game.freeNodes.add(idx.int32)

proc markDirty*(game: var Game; idx: NodeIdx) =
  if idx != NoNodeIdx:
    game.nodes[idx.int].transform.flags.incl(Dirty)

proc initCollide(size: Vec2): Collide =
  Collide(
    size: size,
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  )

proc createBall(game: var Game; x, y: float32; seed: uint32) =
  let angle = angleFromSeed(seed)
  let node = game.allocNode(vec2(x, y), game.camera.node)
  game.balls.add(Ball(
    node: node,
    collide: initCollide(vec2(20, 20)),
    draw: Draw2d(width: 20, height: 20, color: [0'u8, 255, 0, 255]),
    move: Move(direction: Vec2(x: cos(angle), y: sin(angle)), speed: 14)
  ))

proc createBrick(game: var Game; x, y: float32; width, height: int32) =
  let node = game.allocNode(vec2(x, y), game.camera.node)
  game.bricks.add(Brick(
    node: node,
    collide: initCollide(vec2(width.float32, height.float32)),
    draw: Draw2d(width: width, height: height, color: [255'u8, 255, 0, 255]),
    fade: Fade(step: 0),
    dead: false
  ))

proc createExplosion(game: var Game; x, y: float32) =
  let explosions = 32
  let step = TAU / explosions.float
  let fadeStep = 0.05

  for i in 0..<explosions:
    let node = game.allocNode(vec2(x, y), game.camera.node)
    game.particles.add(Particle(
      node: node,
      draw: Draw2d(width: 20, height: 20, color: [255'u8, 255, 255, 255]),
      fade: Fade(step: fadeStep),
      move: Move(
        direction: Vec2(x: sin(step * i.float32), y: cos(step * i.float32)),
        speed: 20
      ),
      dead: false
    ))

proc createTrail(game: var Game; x, y: float32) =
  let node = game.allocNode(vec2(x, y), game.camera.node)
  game.trails.add(Trail(
    node: node,
    draw: Draw2d(width: 20, height: 20, color: [0'u8, 255, 0, 255]),
    fade: Fade(step: 0.05),
    dead: false
  ))

proc createPaddle(game: var Game; x, y: float32) =
  let node = game.allocNode(vec2(x, y), game.camera.node)
  game.paddle = Paddle(
    active: true,
    node: node,
    collide: initCollide(vec2(100, 20)),
    draw: Draw2d(width: 100, height: 20, color: [255'u8, 0, 0, 255]),
    move: Move(direction: vec2(0, 0), speed: 20)
  )

proc createScene*(game: var Game; scale: BenchScale) =
  let columnCount = scale.columns
  let rowCount = scale.rows
  let brickWidth = 50
  let brickHeight = 15
  let margin = 5

  let gridWidth = brickWidth * columnCount + margin * (columnCount - 1)
  let startingX = (game.windowWidth - gridWidth) div 2
  let startingY = 50

  game.camera = Camera(
    node: game.allocNode(vec2(0, 0)),
    shake: Shake(duration: 0, strength: 10)
  )

  game.createPaddle(float32(game.windowWidth / 2), float32(game.windowHeight - 30))
  game.createBall(
    float32(game.windowWidth / 2),
    float32(game.windowHeight - 60),
    eventSeed(1'u32, 0, float32(game.windowWidth / 2), float32(game.windowHeight - 60))
  )

  for row in 0..<rowCount:
    let y = startingY + row * (brickHeight + margin) + brickHeight div 2
    for col in 0..<columnCount:
      let x = startingX + col * (brickWidth + margin) + brickWidth div 2
      game.createBrick(x.float32, y.float32, brickWidth.int32, brickHeight.int32)

proc computeAabb(transform: Transform2d; collide: var Collide) =
  collide.center = transform.world.origin
  collide.min = collide.center - collide.size / 2
  collide.max = collide.center + collide.size / 2

proc intersectAabb(a, b: Collide): bool =
  a.min.x < b.max.x and a.min.y < b.max.y and
    a.max.x > b.min.x and a.max.y > b.min.y

proc penetrateAabb(a, b: Collide): Vec2 =
  let distanceX = a.center.x - b.center.x
  let penetrationX = a.size.x / 2 + b.size.x / 2 - abs(distanceX)
  let distanceY = a.center.y - b.center.y
  let penetrationY = a.size.y / 2 + b.size.y / 2 - abs(distanceY)

  if penetrationX < penetrationY:
    result = vec2(penetrationX * sgn(distanceX).float32, 0)
  else:
    result = vec2(0, penetrationY * sgn(distanceY).float32)

proc prepareCollider(transform: Transform2d; collide: var Collide) =
  collide.collision = Collision(flags: {}, hit: vec2(0, 0))
  computeAabb(transform, collide)

proc updateCollision(a, b: var Collide) =
  if intersectAabb(a, b):
    let hit = penetrateAabb(a, b)
    a.collision = Collision(flags: {Hit}, hit: hit)
    b.collision = Collision(flags: {Hit}, hit: -hit)

proc preparePaddleCollider(game: var Game) =
  if game.paddle.active:
    let transform = game.nodes[game.paddle.node.int].transform
    prepareCollider(transform, game.paddle.collide)

proc prepareBallColliders(game: var Game) =
  for ball in game.balls.mitems:
    let transform = game.nodes[ball.node.int].transform
    prepareCollider(transform, ball.collide)

proc prepareBrickColliders(game: var Game) =
  for brick in game.bricks.mitems:
    if not brick.dead:
      let transform = game.nodes[brick.node.int].transform
      prepareCollider(transform, brick.collide)

proc collideBallWithPaddle(game: var Game; ball: var Ball) =
  if game.paddle.active:
    updateCollision(ball.collide, game.paddle.collide)

proc collideBallWithBricks(game: var Game; ball: var Ball) =
  for brick in game.bricks.mitems:
    if not brick.dead:
      updateCollision(ball.collide, brick.collide)

proc sysCollide*(game: var Game) =
  game.preparePaddleCollider()
  game.prepareBallColliders()
  game.prepareBrickColliders()

  for ball in game.balls.mitems:
    game.collideBallWithPaddle(ball)
    game.collideBallWithBricks(ball)

proc updateBallBounds(game: var Game; ball: var Ball) =
  let node = ball.node
  let size = ball.collide.size

  if ball.collide.min.x < 0:
    game.nodes[node.int].transform.translation.x = size.x / 2
    ball.move.direction.x *= -1

  if ball.collide.max.x > game.windowWidth.float32:
    game.nodes[node.int].transform.translation.x = game.windowWidth.float32 - size.x / 2
    ball.move.direction.x *= -1

  if ball.collide.min.y < 0:
    game.nodes[node.int].transform.translation.y = size.y / 2
    ball.move.direction.y *= -1

  if ball.collide.max.y > game.windowHeight.float32:
    game.nodes[node.int].transform.translation.y = game.windowHeight.float32 - size.y / 2
    ball.move.direction.y *= -1

proc updateBallCollision(game: var Game; ball: var Ball) =
  if Hit in ball.collide.collision.flags:
    game.camera.shake.duration = 0.1

    if ball.collide.collision.hit.x != 0:
      game.nodes[ball.node.int].transform.translation.x += ball.collide.collision.hit.x
      ball.move.direction.x *= -1

    if ball.collide.collision.hit.y != 0:
      game.nodes[ball.node.int].transform.translation.y += ball.collide.collision.hit.y
      ball.move.direction.y *= -1

    let position = game.nodes[ball.node.int].transform.translation
    game.createExplosion(position.x, position.y)

proc updateBallTrail(game: var Game; ball: Ball) =
  let position = game.nodes[ball.node.int].transform.translation
  game.markDirty(ball.node)
  game.createTrail(position.x, position.y)

proc updateBall(game: var Game; ball: var Ball) =
  game.updateBallBounds(ball)
  game.updateBallCollision(ball)
  game.updateBallTrail(ball)

proc sysControlBall*(game: var Game) =
  let ballCount = game.balls.len
  for i in 0..<ballCount:
    game.updateBall(game.balls[i])

proc updateBrick(game: var Game; brick: var Brick) =
  if not brick.dead and Hit in brick.collide.collision.flags:
    brick.fade.step = 0.05
    let position = game.nodes[brick.node.int].transform.translation
    let spawnSeed = eventSeed(2'u32, game.tickId, position.x, position.y)
    if chanceFromSeed(spawnSeed) > 0.98:
      game.createBall(
        float32(game.windowWidth / 2),
        float32(game.windowHeight / 2),
        spawnSeed
      )

proc sysControlBrick*(game: var Game) =
  for brick in game.bricks.mitems:
    game.updateBrick(brick)

proc sysControlPaddle*(game: var Game) =
  if not game.paddle.active:
    return

  game.paddle.move.direction.x = 0
  if game.inputState[Left]:
    game.paddle.move.direction.x -= 1
  if game.inputState[Right]:
    game.paddle.move.direction.x += 1

proc applyFade(game: var Game; node: NodeIdx; draw: var Draw2d; fade: Fade;
    dead: var bool) =
  if draw.color[3] > 0:
    let step = 255 * fade.step
    draw.color[3] = draw.color[3] - step.uint8
    game.nodes[node.int].transform.scale.x -= fade.step
    game.nodes[node.int].transform.scale.y -= fade.step
    game.markDirty(node)
    if game.nodes[node.int].transform.scale.x <= 0:
      dead = true

proc fadeBricks(game: var Game) =
  for brick in game.bricks.mitems:
    if not brick.dead:
      game.applyFade(brick.node, brick.draw, brick.fade, brick.dead)

proc fadeParticles(game: var Game) =
  for particle in game.particles.mitems:
    if not particle.dead:
      game.applyFade(particle.node, particle.draw, particle.fade, particle.dead)

proc fadeTrails(game: var Game) =
  for trail in game.trails.mitems:
    if not trail.dead:
      game.applyFade(trail.node, trail.draw, trail.fade, trail.dead)

proc sysFade*(game: var Game) =
  game.fadeBricks()
  game.fadeParticles()
  game.fadeTrails()

proc cleanupDeadBricks(game: var Game) =
  var i = game.bricks.high
  while i >= 0:
    if game.bricks[i].dead:
      game.freeNode(game.bricks[i].node)
      game.bricks.del(i)
    dec i

proc cleanupDeadParticles(game: var Game) =
  var i = game.particles.high
  while i >= 0:
    if game.particles[i].dead:
      game.freeNode(game.particles[i].node)
      game.particles.del(i)
    dec i

proc cleanupDeadTrails(game: var Game) =
  var i = game.trails.high
  while i >= 0:
    if game.trails[i].dead:
      game.freeNode(game.trails[i].node)
      game.trails.del(i)
    dec i

proc cleanupDead*(game: var Game) =
  game.cleanupDeadBricks()
  game.cleanupDeadParticles()
  game.cleanupDeadTrails()

proc moveNode(game: var Game; node: NodeIdx; move: Move) =
  if move.direction.x != 0 or move.direction.y != 0:
    game.nodes[node.int].transform.translation.x += move.direction.x * move.speed
    game.nodes[node.int].transform.translation.y += move.direction.y * move.speed
    game.markDirty(node)

proc movePaddle(game: var Game) =
  if game.paddle.active:
    game.moveNode(game.paddle.node, game.paddle.move)

proc moveBalls(game: var Game) =
  for ball in game.balls.items:
    game.moveNode(ball.node, ball.move)

proc moveParticles(game: var Game) =
  for particle in game.particles.items:
    if not particle.dead:
      game.moveNode(particle.node, particle.move)

proc sysMove*(game: var Game) =
  game.movePaddle()
  game.moveBalls()
  game.moveParticles()

proc updateCameraShake(game: var Game) =
  let node = game.camera.node

  if game.camera.shake.duration > 0:
    game.camera.shake.duration -= 0.01
    game.nodes[node.int].transform.translation.x =
      shakeOffsetFromTick(game.tickId, 0, game.camera.shake.strength)
    game.nodes[node.int].transform.translation.y =
      shakeOffsetFromTick(game.tickId, 1, game.camera.shake.strength)

    game.clearColor[0] = shakeColorFromTick(game.tickId, 0)
    game.clearColor[1] = shakeColorFromTick(game.tickId, 1)
    game.clearColor[2] = shakeColorFromTick(game.tickId, 2)
    game.markDirty(node)

    if game.camera.shake.duration <= 0:
      game.camera.shake.duration = 0
      game.nodes[node.int].transform.translation.x = 0
      game.nodes[node.int].transform.translation.y = 0
      game.clearColor[0] = 0
      game.clearColor[1] = 0
      game.clearColor[2] = 0
      game.markDirty(node)

proc sysShake*(game: var Game) =
  game.updateCameraShake()

proc updateTransformWorld(game: var Game; idx: NodeIdx) =
  if Fresh in game.nodes[idx.int].transform.flags:
    game.nodes[idx.int].transform.flags.excl(Fresh)
  else:
    game.nodes[idx.int].previous.position = game.nodes[idx.int].transform.world.origin
    game.nodes[idx.int].previous.rotation = game.nodes[idx.int].transform.world.rotation
    game.nodes[idx.int].previous.scale = game.nodes[idx.int].transform.world.scale
    game.nodes[idx.int].transform.flags.incl(HasPrevious)
    game.nodes[idx.int].transform.flags.excl(Dirty)

  let local = compose(
    game.nodes[idx.int].transform.scale,
    game.nodes[idx.int].transform.rotation,
    game.nodes[idx.int].transform.translation
  )
  let parent = game.parent(idx)
  if parent != NoNodeIdx:
    game.nodes[idx.int].transform.world = game.nodes[parent.int].transform.world * local
  else:
    game.nodes[idx.int].transform.world = local

proc sysTransform2d*(game: var Game) =
  var stack: seq[NodeIdx] = @[]
  var current = game.camera.node

  while current != NoNodeIdx:
    let sibling = game.nextSibling(current)
    if sibling != NoNodeIdx:
      stack.add(sibling)

    if game.nodes[current.int].transform.flags.intersects({Dirty, Fresh}):
      game.updateTransformWorld(current)

    let child = game.firstChild(current)
    if child != NoNodeIdx:
      current = child
    elif stack.len > 0:
      current = stack.pop()
    else:
      current = NoNodeIdx
