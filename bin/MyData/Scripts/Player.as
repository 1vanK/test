// ==============================================
//
//    Player Pawn and Controller Class
//
// ==============================================


class PlayerStandState : MultiAnimationState
{
    PlayerStandState(Character@ c)
    {
        super(c);
        SetName("StandState");
        looped = true;
    }

    void Enter(State@ lastState)
    {
        ownner.SetVelocity(Vector3(0,0,0));
        MultiAnimationState::Enter(lastState);
    }

    void Update(float dt)
    {
        if (!gInput.IsLeftStickInDeadZone() && gInput.IsLeftStickStationary())
        {
            ownner.ChangeState(gInput.IsRunHolding() ? "RunState" : "WalkState");
            return;
        }

        if (ownner.CheckFalling())
            return;

        MultiAnimationState::Update(dt);
    }

    int PickIndex()
    {
        return RandomInt(animations.length);
    }
};

class PlayerMoveForwardState : SingleAnimationState
{
    Vector3 velocity = Vector3(0, 0, 3.5f);
    float turnSpeed = 5.0f;

    PlayerMoveForwardState(Character@ c)
    {
        super(c);
        flags = FLAGS_MOVING;
        looped = true;
    }

    void OnStop()
    {
        ownner.ChangeState("StandState");
    }

    void Update(float dt)
    {
        float characterDifference = ownner.ComputeAngleDiff();
        Node@ _node = ownner.GetNode();
        _node.Yaw(characterDifference * turnSpeed * dt);

        if (gInput.IsLeftStickInDeadZone() && gInput.HasLeftStickBeenStationary(0.1f))
        {
            OnStop();
            return;
        }

        if (ownner.CheckFalling())
            return;

        ownner.SetVelocity(ownner.GetNode().worldRotation * velocity);

        SingleAnimationState::Update(dt);
    }
};

class PlayerWalkState : PlayerMoveForwardState
{
    PlayerWalkState(Character@ c)
    {
        super(c);
        SetName("WalkState");
        turnSpeed = 5.0f;
    }

    void Update(float dt)
    {
        if (gInput.IsRunHolding())
        {
            ownner.ChangeState("RunState");
            return;
        }

        PlayerMoveForwardState::Update(dt);
    }
};

class PlayerRunState : PlayerMoveForwardState
{
    PlayerRunState(Character@ c)
    {
        super(c);
        SetName("RunState");
        turnSpeed = 7.5f;
        flags |= FLAGS_RUN;
        velocity = Vector3(0, 0, 5.5f);
    }

    void Update(float dt)
    {
        if (!gInput.IsRunHolding())
        {
            ownner.ChangeState("WalkState");
            return;
        }

        PlayerMoveForwardState::Update(dt);
    }
};

class PlayerFallState : SingleAnimationState
{
    PlayerFallState(Character@ c)
    {
        super(c);
        SetName("FallState");
    }

    void Update(float dt)
    {
        Player@ p = cast<Player@>(ownner);
        if (p.sensor.grounded)
        {
            ownner.ChangeState("StandState");
            return;
        }
        SingleAnimationState::Update(dt);
    }

    void OnMotionFinished()
    {
    }
};

class Player : Character
{
    bool                              applyGravity = true;
    Node@                             objectCollectsNode;
    Array<Interactable@>              objectCollection;

    void ObjectStart()
    {
        Character::ObjectStart();

        side = 1;
        @sensor = PhysicsSensor(sceneNode);
        objectCollectsNode = GetScene().CreateChild("Player_ObjectsCollectsNode");
        CollisionShape@ shape = objectCollectsNode.CreateComponent("CollisionShape");
        float coneHeight = 9.0f;
        float coneRadius = 3.0f;
        shape.SetCone(coneRadius * 2, coneHeight, Vector3(0, 0, coneHeight/4*3), Quaternion(-90, 0, 0));
        RigidBody@ body = objectCollectsNode.CreateComponent("RigidBody");
        body.collisionMask = 0;

        body.collisionLayer = COLLISION_LAYER_RAYCAST;
        body.collisionMask = COLLISION_LAYER_PROP;

        AddStates();
        ChangeState("StandState");
    }

    void AddStates()
    {
    }


    void CommonStateFinishedOnGroud()
    {
        if (CheckFalling())
            return;

        if (!gInput.IsLeftStickInDeadZone() && gInput.IsLeftStickStationary())
            ChangeState(gInput.IsRunHolding() ? "RunState" : "WalkState");
        else
            ChangeState("StandState");
    }

    float GetTargetAngle()
    {
        return gInput.GetLeftAxisAngle() + gCameraMgr.GetCameraAngle();
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        Character::DebugDraw(debug);
        // debug.AddCircle(sceneNode.worldPosition, Vector3(0, 1, 0), COLLISION_RADIUS, YELLOW, 32, false);
        // sensor.DebugDraw(debug);
        debug.AddNode(sceneNode.GetChild(TranslateBoneName, true), 0.5f, false);
    }

    void Update(float dt)
    {
        sensor.Update(dt);
        CollectObjectsInView(objectCollection);
        Character::Update(dt);
    }

    void SetVelocity(const Vector3&in vel)
    {
        if (!sensor.grounded && applyGravity)
            Character::SetVelocity(vel + Vector3(0, -9.8f, 0));
        else
            Character::SetVelocity(vel);
    }

    bool CheckFalling()
    {
        if (!sensor.grounded && sensor.inAirHeight > 1.5f && sensor.inAirFrames > 2 && applyGravity)
        {
            ChangeState("FallState");
            return true;
        }
        return false;
    }

    void CollectObjectsInView(Array<Interactable@>@ outObjects)
    {
        for (uint i=0; i<outObjects.length; ++i)
        {
            outObjects[i].ShowOverlay(false);
        }

        outObjects.Clear();
        objectCollectsNode.worldPosition = gCameraMgr.cameraNode.worldPosition;
        objectCollectsNode.worldRotation = gCameraMgr.cameraNode.worldRotation;

        Array<RigidBody@>@ bodies = physicsWorld.GetRigidBodies(objectCollectsNode.GetComponent("RigidBody"));
        for (uint i=0; i<bodies.length; ++i)
        {
            Interactable@ it = cast<Interactable>(bodies[i].node.scriptObject);
            if (it !is null)
            {
                outObjects.Push(it);
                it.ShowOverlay(true);
                // Print("Found object " + bodies[i].node.name);
            }
        }
    }
};
