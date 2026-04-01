import std/[math, random]
from typetraits import supportsCopyMem
import ../../shared/[headless_raylib, vmath]
# ---- archetype ecs runtime ----

const
  EntityIndexBits = 20'u32
  EntityIndexMask = (1'u32 shl EntityIndexBits) - 1
  ArchetypeShift = 28'u32
  ArchetypeRowMask = (1'u32 shl ArchetypeShift) - 1
  InvalidLocation = high(uint32)
  InvalidSlot = -1'i32

type
  Input* = enum
    Right, Left

  CollisionFlag* = enum
    Hit

  TransformFlag* = enum
    Dirty, Fresh, HasPrevious

  ComponentKind = enum
    TransformC,
    HierarchyC,
    PreviousC,
    CollideC,
    Draw2dC,
    FadeC,
    MoveC,
    ShakeC

  ArchetypeKind* = enum
    CameraArch = 0,
    PaddleArch = 1,
    BallArch = 2,
    BrickArch = 3,
    ParticleArch = 4,
    TrailArch = 5

  Entity* = distinct uint32

  Collision* = object
    flags*: set[CollisionFlag]
    hit*: Vec2

  Hierarchy* = object
    head*: Entity
    prev*: Entity
    next*: Entity
    parent*: Entity

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

  Actor* = object
    entity*: Entity
    dead*: bool

  EntitySlot = object
    generation: uint16
    nextFree: int32
    location: uint32

  DenseVec*[T] = object
    len*: int32
    cap*: int32
    data*: ptr UncheckedArray[T]

  Archetype = object
    mask: set[ComponentKind]
    entities: DenseVec[Entity]
    columns: array[ComponentKind, pointer]

  Game* = object
    camera*: Entity
    paddle*: Entity
    actors*: seq[Actor]

    archetypes: array[ArchetypeKind, Archetype]
    slots: seq[EntitySlot]
    freeHead: int32

    inputState*: array[Input, bool]
    clearColor*: array[4, uint8]

    isRunning*: bool
    windowWidth*, windowHeight*: int32
    tickId*: int

    raylib*: RaylibContext

const
  NoEntity* = Entity(high(uint32))

proc `==`*(a, b: Entity): bool {.borrow.}

func intersects*[K: enum](a, b: set[K]): bool {.inline.} =
  (a * b) != {}

proc `=destroy`*[T](x: var DenseVec[T]) =
  if x.data != nil:
    when not supportsCopyMem(T):
      for i in 0..<x.len.int:
        `=destroy`(x.data[i])
    dealloc(x.data)

proc `=wasMoved`*[T](x: var DenseVec[T]) =
  x.len = 0
  x.cap = 0
  x.data = nil

proc `=copy`*[T](dest: var DenseVec[T]; src: DenseVec[T]) {.error.}
proc `=dup`*[T](src: DenseVec[T]): DenseVec[T] {.error.}

proc `[]`*[T](x: DenseVec[T]; idx: int32): lent T {.inline.} =
  x.data[idx]

proc `[]`*[T](x: var DenseVec[T]; idx: int32): var T {.inline.} =
  x.data[idx]

proc grow[T](x: var DenseVec[T]; needed: int32) =
  var newCap = if x.cap > 0: x.cap else: 8'i32
  while newCap < needed:
    newCap = newCap shl 1
  let newData = cast[ptr UncheckedArray[T]](alloc(newCap.int * sizeof(T)))
  when supportsCopyMem(T):
    if x.len > 0:
      copyMem(addr newData[0], addr x.data[0], x.len.int * sizeof(T))
  else:
    for i in 0..<x.len.int:
      newData[i] = move(x.data[i.int32])
  if x.data != nil:
    dealloc(x.data)
  x.data = newData
  x.cap = newCap

proc add[T](x: var DenseVec[T]; value: sink T) {.inline.} =
  if x.len == x.cap:
    x.grow(x.len + 1)
  x.data[x.len] = value
  inc x.len

proc removeAt[T](x: var DenseVec[T]; idx: int32) {.inline.} =
  let last = x.len - 1
  when not supportsCopyMem(T):
    `=destroy`(x.data[idx])
  if idx != last:
    x.data[idx] = move(x.data[last])
  dec x.len

proc newColumn[T](): pointer =
  result = alloc0(sizeof(DenseVec[T]))

proc destroyColumn[T](column: pointer) =
  if column != nil:
    var value = cast[ptr DenseVec[T]](column)
    `=destroy`(value[])
    dealloc(column)

proc `=destroy`(x: var Archetype) =
  `=destroy`(x.entities)
  if TransformC in x.mask:
    destroyColumn[Transform2d](x.columns[TransformC])
  if HierarchyC in x.mask:
    destroyColumn[Hierarchy](x.columns[HierarchyC])
  if PreviousC in x.mask:
    destroyColumn[Previous](x.columns[PreviousC])
  if CollideC in x.mask:
    destroyColumn[Collide](x.columns[CollideC])
  if Draw2dC in x.mask:
    destroyColumn[Draw2d](x.columns[Draw2dC])
  if FadeC in x.mask:
    destroyColumn[Fade](x.columns[FadeC])
  if MoveC in x.mask:
    destroyColumn[Move](x.columns[MoveC])
  if ShakeC in x.mask:
    destroyColumn[Shake](x.columns[ShakeC])

proc `=wasMoved`(x: var Archetype) =
  `=wasMoved`(x.entities)
  x.mask = {}
  for comp in ComponentKind:
    x.columns[comp] = nil

proc `=copy`(dest: var Archetype; src: Archetype) {.error.}
proc `=dup`(src: Archetype): Archetype {.error.}

func slotIndex(entity: Entity): int32 {.inline.} =
  int32(entity.uint32 and EntityIndexMask)

func generationBits(entity: Entity): uint16 {.inline.} =
  uint16(entity.uint32 shr EntityIndexBits)

func packEntity(slot: int32; generation: uint16): Entity {.inline.} =
  Entity((uint32(generation) shl EntityIndexBits) or uint32(slot))

func packLocation(kind: ArchetypeKind; row: int32): uint32 {.inline.} =
  (uint32(kind.ord) shl ArchetypeShift) or uint32(row)

func locationKind(location: uint32): ArchetypeKind {.inline.} =
  ArchetypeKind((location shr ArchetypeShift).int)

func locationRow(location: uint32): int32 {.inline.} =
  int32(location and ArchetypeRowMask)

proc initArchetype(mask: set[ComponentKind]): Archetype =
  result = Archetype(mask: mask)
  if TransformC in mask:
    result.columns[TransformC] = newColumn[Transform2d]()
  if HierarchyC in mask:
    result.columns[HierarchyC] = newColumn[Hierarchy]()
  if PreviousC in mask:
    result.columns[PreviousC] = newColumn[Previous]()
  if CollideC in mask:
    result.columns[CollideC] = newColumn[Collide]()
  if Draw2dC in mask:
    result.columns[Draw2dC] = newColumn[Draw2d]()
  if FadeC in mask:
    result.columns[FadeC] = newColumn[Fade]()
  if MoveC in mask:
    result.columns[MoveC] = newColumn[Move]()
  if ShakeC in mask:
    result.columns[ShakeC] = newColumn[Shake]()

proc initArchetypes(game: var Game) =
  game.archetypes[CameraArch] = initArchetype({TransformC, HierarchyC, PreviousC, ShakeC})
  game.archetypes[PaddleArch] = initArchetype({TransformC, HierarchyC, PreviousC, CollideC, Draw2dC, MoveC})
  game.archetypes[BallArch] = initArchetype({TransformC, HierarchyC, PreviousC, CollideC, Draw2dC, MoveC})
  game.archetypes[BrickArch] = initArchetype({TransformC, HierarchyC, PreviousC, CollideC, Draw2dC, FadeC})
  game.archetypes[ParticleArch] = initArchetype({TransformC, HierarchyC, PreviousC, Draw2dC, FadeC, MoveC})
  game.archetypes[TrailArch] = initArchetype({TransformC, HierarchyC, PreviousC, Draw2dC, FadeC})

template column(game: untyped; kind: ArchetypeKind; comp: static[ComponentKind]; T: typedesc): untyped =
  cast[ptr DenseVec[T]](game.archetypes[kind].columns[comp])[]

func entityArch(game: Game; entity: Entity): ArchetypeKind {.inline.} =
  game.slots[entity.slotIndex].location.locationKind

func entityRow(game: Game; entity: Entity): int32 {.inline.} =
  game.slots[entity.slotIndex].location.locationRow

func hasComponent(game: Game; entity: Entity; comp: ComponentKind): bool {.inline.} =
  comp in game.archetypes[game.entityArch(entity)].mask

template denseColumn(game: untyped; entity: Entity; comp: static[ComponentKind];
    T: typedesc): untyped =
  game.column(game.entityArch(entity), comp, T)

proc componentPtr[T](game: var Game; entity: Entity; comp: static[ComponentKind]): ptr T {.inline.} =
  let row = game.entityRow(entity)
  addr game.denseColumn(entity, comp, T)[row]

proc componentPtr[T](game: Game; entity: Entity; comp: static[ComponentKind]): ptr T {.inline.} =
  let row = game.entityRow(entity)
  addr game.denseColumn(entity, comp, T)[row]

proc ensureInit(game: var Game) =
  if game.archetypes[CameraArch].columns[TransformC] == nil:
    game.initArchetypes()
    game.freeHead = InvalidSlot

proc allocEntity(game: var Game; kind: ArchetypeKind): Entity =
  let arch = addr game.archetypes[kind]
  let row = arch[].entities.len
  if game.freeHead != InvalidSlot:
    let slot = game.freeHead
    game.freeHead = game.slots[slot].nextFree
    game.slots[slot] = EntitySlot(
      generation: game.slots[slot].generation,
      nextFree: InvalidSlot,
      location: packLocation(kind, row)
    )
    result = packEntity(slot, game.slots[slot].generation)
  else:
    let slot = game.slots.len.int32
    game.slots.add(EntitySlot(
      generation: 1'u16,
      nextFree: InvalidSlot,
      location: packLocation(kind, row)
    ))
    result = packEntity(slot, 1'u16)
  arch[].entities.add(result)

proc freeSlot(game: var Game; entity: Entity) =
  let slot = entity.slotIndex
  game.slots[slot].generation = game.slots[slot].generation + 1
  game.slots[slot].location = InvalidLocation
  game.slots[slot].nextFree = game.freeHead
  game.freeHead = slot

proc parentOf*(game: Game; entity: Entity): Entity {.inline.} =
  componentPtr[Hierarchy](game, entity, HierarchyC)[].parent

proc firstChild*(game: Game; entity: Entity): Entity {.inline.} =
  componentPtr[Hierarchy](game, entity, HierarchyC)[].head

proc nextSibling*(game: Game; entity: Entity): Entity {.inline.} =
  componentPtr[Hierarchy](game, entity, HierarchyC)[].next

proc markDirty*(game: var Game; entity: Entity) =
  if entity != NoEntity:
    componentPtr[Transform2d](game, entity, TransformC)[].flags.incl(Dirty)

proc prependChild(game: var Game; parent, child: Entity) =
  template childHierarchy: untyped = componentPtr[Hierarchy](game, child, HierarchyC)[]
  template parentHierarchy: untyped = componentPtr[Hierarchy](game, parent, HierarchyC)[]
  childHierarchy.parent = parent
  childHierarchy.prev = NoEntity
  childHierarchy.next = parentHierarchy.head
  if parentHierarchy.head != NoEntity:
    componentPtr[Hierarchy](game, parentHierarchy.head, HierarchyC)[].prev = child
  parentHierarchy.head = child

proc removeNode(game: var Game; entity: Entity) =
  template hierarchy: untyped = componentPtr[Hierarchy](game, entity, HierarchyC)[]
  let parent = hierarchy.parent
  let prev = hierarchy.prev
  let next = hierarchy.next
  let head = hierarchy.head

  if parent != NoEntity and componentPtr[Hierarchy](game, parent, HierarchyC)[].head == entity:
    componentPtr[Hierarchy](game, parent, HierarchyC)[].head = next
  if prev != NoEntity:
    componentPtr[Hierarchy](game, prev, HierarchyC)[].next = next
  if next != NoEntity:
    componentPtr[Hierarchy](game, next, HierarchyC)[].prev = prev

  hierarchy = Hierarchy(
    head: head,
    prev: NoEntity,
    next: NoEntity,
    parent: NoEntity
  )

proc initTransform(translation: Vec2): Transform2d =
  Transform2d(
    world: mat2d(),
    translation: translation,
    rotation: 0.Rad,
    scale: vec2(1, 1),
    flags: {Dirty, Fresh}
  )

proc initHierarchy(): Hierarchy =
  Hierarchy(head: NoEntity, prev: NoEntity, next: NoEntity, parent: NoEntity)

proc initPrevious(): Previous =
  Previous(position: point2(0, 0), rotation: 0.Rad, scale: vec2(1, 1))

proc addActor(game: var Game; entity: Entity) =
  game.actors.add(Actor(entity: entity, dead: false))

proc addCamera(game: var Game; translation: Vec2): Entity =
  result = game.allocEntity(CameraArch)
  game.column(CameraArch, TransformC, Transform2d).add(initTransform(translation))
  game.column(CameraArch, HierarchyC, Hierarchy).add(initHierarchy())
  game.column(CameraArch, PreviousC, Previous).add(initPrevious())
  game.column(CameraArch, ShakeC, Shake).add(Shake(duration: 0, strength: 10))

proc addPaddleEntity(game: var Game; translation: Vec2): Entity =
  result = game.allocEntity(PaddleArch)
  game.column(PaddleArch, TransformC, Transform2d).add(initTransform(translation))
  game.column(PaddleArch, HierarchyC, Hierarchy).add(initHierarchy())
  game.column(PaddleArch, PreviousC, Previous).add(initPrevious())
  game.column(PaddleArch, CollideC, Collide).add(Collide(
    size: vec2(100, 20),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  ))
  game.column(PaddleArch, Draw2dC, Draw2d).add(Draw2d(
    width: 100,
    height: 20,
    color: [255'u8, 0, 0, 255]
  ))
  game.column(PaddleArch, MoveC, Move).add(Move(direction: vec2(0, 0), speed: 20))
  game.prependChild(game.camera, result)
  game.addActor(result)

proc createBall*(game: var Game; x, y: float32) =
  let angle = PI.float32 + rand(1.0'f32) * PI.float32
  let entity = game.allocEntity(BallArch)
  game.column(BallArch, TransformC, Transform2d).add(initTransform(vec2(x, y)))
  game.column(BallArch, HierarchyC, Hierarchy).add(initHierarchy())
  game.column(BallArch, PreviousC, Previous).add(initPrevious())
  game.column(BallArch, CollideC, Collide).add(Collide(
    size: vec2(20, 20),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  ))
  game.column(BallArch, Draw2dC, Draw2d).add(Draw2d(
    width: 20,
    height: 20,
    color: [0'u8, 255, 0, 255]
  ))
  game.column(BallArch, MoveC, Move).add(Move(
    direction: Vec2(x: cos(angle), y: sin(angle)),
    speed: 14
  ))
  game.prependChild(game.camera, entity)
  game.addActor(entity)

proc createBrick*(game: var Game; x, y: float32; width, height: int32) =
  let entity = game.allocEntity(BrickArch)
  game.column(BrickArch, TransformC, Transform2d).add(initTransform(vec2(x, y)))
  game.column(BrickArch, HierarchyC, Hierarchy).add(initHierarchy())
  game.column(BrickArch, PreviousC, Previous).add(initPrevious())
  game.column(BrickArch, CollideC, Collide).add(Collide(
    size: vec2(width.float32, height.float32),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  ))
  game.column(BrickArch, Draw2dC, Draw2d).add(Draw2d(
    width: width,
    height: height,
    color: [255'u8, 255, 0, 255]
  ))
  game.column(BrickArch, FadeC, Fade).add(Fade(step: 0))
  game.prependChild(game.camera, entity)
  game.addActor(entity)

proc createExplosion*(game: var Game; x, y: float32) =
  let explosions = 32
  let step = TAU / explosions.float
  let fadeStep = 0.05
  for i in 0..<explosions:
    let entity = game.allocEntity(ParticleArch)
    game.column(ParticleArch, TransformC, Transform2d).add(initTransform(vec2(x, y)))
    game.column(ParticleArch, HierarchyC, Hierarchy).add(initHierarchy())
    game.column(ParticleArch, PreviousC, Previous).add(initPrevious())
    game.column(ParticleArch, Draw2dC, Draw2d).add(Draw2d(
      width: 20,
      height: 20,
      color: [255'u8, 255, 255, 255]
    ))
    game.column(ParticleArch, FadeC, Fade).add(Fade(step: fadeStep))
    game.column(ParticleArch, MoveC, Move).add(Move(
      direction: Vec2(x: sin(step * i.float32), y: cos(step * i.float32)),
      speed: 20
    ))
    game.prependChild(game.camera, entity)
    game.addActor(entity)

proc createTrail*(game: var Game; x, y: float32) =
  let entity = game.allocEntity(TrailArch)
  game.column(TrailArch, TransformC, Transform2d).add(initTransform(vec2(x, y)))
  game.column(TrailArch, HierarchyC, Hierarchy).add(initHierarchy())
  game.column(TrailArch, PreviousC, Previous).add(initPrevious())
  game.column(TrailArch, Draw2dC, Draw2d).add(Draw2d(
    width: 20,
    height: 20,
    color: [0'u8, 255, 0, 255]
  ))
  game.column(TrailArch, FadeC, Fade).add(Fade(step: 0.05))
  game.prependChild(game.camera, entity)
  game.addActor(entity)

proc createPaddle*(game: var Game; x, y: float32) =
  game.paddle = game.addPaddleEntity(vec2(x, y))

proc createScene*(game: var Game) =
  game.ensureInit()
  let columnCount = 10
  let rowCount = 10
  let brickWidth = 50
  let brickHeight = 15
  let margin = 5

  let gridWidth = brickWidth * columnCount + margin * (columnCount - 1)
  let startingX = (game.windowWidth - gridWidth) div 2
  let startingY = 50

  game.camera = game.addCamera(vec2(0, 0))
  game.createPaddle(float32(game.windowWidth / 2), float32(game.windowHeight - 30))
  game.createBall(float32(game.windowWidth / 2), float32(game.windowHeight - 60))

  for row in 0..<rowCount:
    let y = startingY + row * (brickHeight + margin) + brickHeight div 2
    for col in 0..<columnCount:
      let x = startingX + col * (brickWidth + margin) + brickWidth div 2
      game.createBrick(x.float32, y.float32, brickWidth.int32, brickHeight.int32)

proc swapMovedEntity(game: var Game; kind: ArchetypeKind; removedRow: int32) =
  let entities = addr game.archetypes[kind].entities
  if removedRow < entities[].len:
    let moved = entities[][removedRow]
    game.slots[moved.slotIndex].location = packLocation(kind, removedRow)

proc removeFromArchetype(game: var Game; entity: Entity) =
  let kind = game.entityArch(entity)
  let row = game.entityRow(entity)
  if kind == CameraArch:
    game.column(kind, ShakeC, Shake).removeAt(row)
  if FadeC in game.archetypes[kind].mask:
    game.column(kind, FadeC, Fade).removeAt(row)
  if MoveC in game.archetypes[kind].mask:
    game.column(kind, MoveC, Move).removeAt(row)
  if Draw2dC in game.archetypes[kind].mask:
    game.column(kind, Draw2dC, Draw2d).removeAt(row)
  if CollideC in game.archetypes[kind].mask:
    game.column(kind, CollideC, Collide).removeAt(row)
  game.column(kind, PreviousC, Previous).removeAt(row)
  game.column(kind, HierarchyC, Hierarchy).removeAt(row)
  game.column(kind, TransformC, Transform2d).removeAt(row)
  game.archetypes[kind].entities.removeAt(row)
  game.swapMovedEntity(kind, row)

proc removeActor(game: var Game; idx: int) =
  let actor = game.actors[idx]
  if actor.entity == game.paddle:
    game.paddle = NoEntity
  game.removeNode(actor.entity)
  game.removeFromArchetype(actor.entity)
  game.freeSlot(actor.entity)
  game.actors.del(idx)

proc archetypeOf*(game: Game; entity: Entity): ArchetypeKind {.inline.} =
  game.entityArch(entity)

proc updateTransformWorld(game: var Game; entity: Entity) =
  template transform: untyped = componentPtr[Transform2d](game, entity, TransformC)[]
  template previous: untyped = componentPtr[Previous](game, entity, PreviousC)[]

  if Fresh in transform.flags:
    transform.flags.excl(Fresh)
  else:
    previous.position = transform.world.origin
    previous.rotation = transform.world.rotation
    previous.scale = transform.world.scale
    transform.flags.incl(HasPrevious)
    transform.flags.excl(Dirty)

  let local = compose(transform.scale, transform.rotation, transform.translation)
  let parent = game.parentOf(entity)
  if parent != NoEntity:
    transform.world = componentPtr[Transform2d](game, parent, TransformC)[].world * local
  else:
    transform.world = local

proc sysTransform2d*(game: var Game) =
  var stack: seq[Entity] = @[]
  var current = game.camera

  while current != NoEntity:
    let sibling = game.nextSibling(current)
    if sibling != NoEntity:
      stack.add(sibling)

    if componentPtr[Transform2d](game, current, TransformC)[].flags.intersects({Dirty, Fresh}):
      game.updateTransformWorld(current)

    let child = game.firstChild(current)
    if child != NoEntity:
      current = child
    elif stack.len > 0:
      current = stack.pop()
    else:
      current = NoEntity

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

proc prepareCollider(game: var Game; entity: Entity) =
  template collider: untyped = componentPtr[Collide](game, entity, CollideC)[]
  collider.collision = Collision(flags: {}, hit: vec2(0, 0))
  computeAabb(componentPtr[Transform2d](game, entity, TransformC)[], collider)

proc updateCollision(game: var Game; aEntity, bEntity: Entity) =
  let a = componentPtr[Collide](game, aEntity, CollideC)[]
  let b = componentPtr[Collide](game, bEntity, CollideC)[]
  if intersectAabb(a, b):
    let hit = penetrateAabb(a, b)
    componentPtr[Collide](game, aEntity, CollideC)[].collision =
      Collision(flags: {Hit}, hit: hit)
    componentPtr[Collide](game, bEntity, CollideC)[].collision =
      Collision(flags: {Hit}, hit: -hit)

proc sysCollide*(game: var Game) =
  if game.paddle != NoEntity:
    game.prepareCollider(game.paddle)

  for actor in game.actors.items:
    if not actor.dead and game.entityArch(actor.entity) in {BallArch, BrickArch}:
      game.prepareCollider(actor.entity)

  for ball in game.actors.items:
    if not ball.dead and game.entityArch(ball.entity) == BallArch:
      if game.paddle != NoEntity:
        game.updateCollision(ball.entity, game.paddle)

      for brick in game.actors.items:
        if not brick.dead and game.entityArch(brick.entity) == BrickArch:
          game.updateCollision(ball.entity, brick.entity)

proc sysControlPaddle*(game: var Game) =
  if game.paddle == NoEntity:
    return
  template move: untyped = componentPtr[Move](game, game.paddle, MoveC)[]
  move.direction.x = 0
  if game.inputState[Left]:
    move.direction.x -= 1
  if game.inputState[Right]:
    move.direction.x += 1

proc sysControlBall*(game: var Game) =
  let actorCount = game.actors.len
  for i in 0..<actorCount:
    template ball: untyped = game.actors[i]
    if not ball.dead and game.entityArch(ball.entity) == BallArch:
      template collide: untyped = componentPtr[Collide](game, ball.entity, CollideC)[]
      template move: untyped = componentPtr[Move](game, ball.entity, MoveC)[]
      template transform: untyped = componentPtr[Transform2d](game, ball.entity, TransformC)[]

      if collide.min.x < 0:
        transform.translation.x = collide.size.x / 2
        move.direction.x *= -1

      if collide.max.x > game.windowWidth.float32:
        transform.translation.x = game.windowWidth.float32 - collide.size.x / 2
        move.direction.x *= -1

      if collide.min.y < 0:
        transform.translation.y = collide.size.y / 2
        move.direction.y *= -1

      if collide.max.y > game.windowHeight.float32:
        transform.translation.y = game.windowHeight.float32 - collide.size.y / 2
        move.direction.y *= -1

      if Hit in collide.collision.flags:
        componentPtr[Shake](game, game.camera, ShakeC)[].duration = 0.1

        if collide.collision.hit.x != 0:
          transform.translation.x += collide.collision.hit.x
          move.direction.x *= -1

        if collide.collision.hit.y != 0:
          transform.translation.y += collide.collision.hit.y
          move.direction.y *= -1

        game.createExplosion(transform.translation.x, transform.translation.y)

      game.markDirty(ball.entity)
      game.createTrail(transform.translation.x, transform.translation.y)

proc sysControlBrick*(game: var Game) =
  let actorCount = game.actors.len
  for i in 0..<actorCount:
    template brick: untyped = game.actors[i]
    if not brick.dead and game.entityArch(brick.entity) == BrickArch and
        Hit in componentPtr[Collide](game, brick.entity, CollideC)[].collision.flags:
      componentPtr[Fade](game, brick.entity, FadeC)[].step = 0.05
      if rand(1.0) > 0.98:
        game.createBall(
          float32(game.windowWidth / 2),
          float32(game.windowHeight / 2)
        )

proc sysShake*(game: var Game) =
  template transform: untyped = componentPtr[Transform2d](game, game.camera, TransformC)[]
  template shake: untyped = componentPtr[Shake](game, game.camera, ShakeC)[]

  if shake.duration > 0:
    shake.duration -= 0.01
    transform.translation.x = shake.strength - rand(shake.strength * 2)
    transform.translation.y = shake.strength - rand(shake.strength * 2)

    game.clearColor[0] = rand(255).uint8
    game.clearColor[1] = rand(255).uint8
    game.clearColor[2] = rand(255).uint8
    game.markDirty(game.camera)

    if shake.duration <= 0:
      shake.duration = 0
      transform.translation.x = 0
      transform.translation.y = 0
      game.clearColor[0] = 0
      game.clearColor[1] = 0
      game.clearColor[2] = 0
      game.markDirty(game.camera)

proc updateFading(game: var Game; actor: var Actor) =
  template transform: untyped = componentPtr[Transform2d](game, actor.entity, TransformC)[]
  template draw: untyped = componentPtr[Draw2d](game, actor.entity, Draw2dC)[]
  let fade = componentPtr[Fade](game, actor.entity, FadeC)[]

  if draw.color[3] > 0:
    let step = 255 * fade.step
    draw.color[3] = draw.color[3] - step.uint8
    transform.scale.x -= fade.step
    transform.scale.y -= fade.step
    game.markDirty(actor.entity)

    if transform.scale.x <= 0:
      actor.dead = true

proc sysFade*(game: var Game) =
  for actor in mitems(game.actors):
    if not actor.dead and game.hasComponent(actor.entity, FadeC):
      game.updateFading(actor)

proc cleanupDead*(game: var Game) =
  for i in countdown(game.actors.high, 0):
    if game.actors[i].dead:
      game.removeActor(i)

proc updateTransform(game: var Game; entity: Entity) =
  let move = componentPtr[Move](game, entity, MoveC)[]
  if move.direction.x != 0 or move.direction.y != 0:
    template transform: untyped = componentPtr[Transform2d](game, entity, TransformC)[]
    transform.translation.x += move.direction.x * move.speed
    transform.translation.y += move.direction.y * move.speed
    game.markDirty(entity)

proc sysMove*(game: var Game) =
  for actor in game.actors.items:
    if not actor.dead and game.entityArch(actor.entity) in {PaddleArch, BallArch, ParticleArch}:
      game.updateTransform(actor.entity)
