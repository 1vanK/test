#include "Scripts/Test/Character.as"

class PlayerStandState : CharacterState
{
    Array<String>           animations;
    int                     selectIndex;

    PlayerStandState(Character@ c)
    {
        super(c);
        name = "StandState";
        animations.Push("Animation/Stand_Idle.ani");
    }

    void Enter(State@ lastState)
    {
        float blendTime = 1.0f;
        if (lastState is null)
            blendTime = 0.1f;
        else if(lastState.name == "MoveState")
            blendTime = 0.2f;
        else if(lastState.name == "EvadeState")
            blendTime = 0.25f;
        selectIndex = RandomInt(animations.length);
        PlayAnimation(ownner.animCtrl, animations[selectIndex], LAYER_MOVE, true, blendTime);
    }

    void Update(float dt)
    {
        if (!gInput.IsLeftStickInDeadZone() && gInput.IsLeftStickStationary())
        {
            int index = RadialSelectAnimation_Player(ownner.sceneNode, 4);
            ownner.sceneNode.vars["AnimationIndex"] = index;
            if (index == 0)
                ownner.stateMachine.ChangeState("MoveState");
            else
                ownner.stateMachine.ChangeState("StandToMoveState");
        }

        if (gInput.IsAttackPressed())
            ownner.Attack();
        else if(gInput.IsCounterPressed())
            ownner.Counter();
    }
};

class PlayerStandToMoveState : MultiMotionState
{
    PlayerStandToMoveState(Character@ c)
    {
        super(c);
        name = "StandToMoveState";
        motions.Push(Motion("Animation/Turn_Right_90.ani", 90, 15, false, false));
        motions.Push(Motion("Animation/Turn_Right_180.ani", 180, 23, false, false));
        motions.Push(Motion("Animation/Turn_Left_90.ani", -90, 16, false, false));
        // motions.Push(Motion("Animation/Stand_To_Walk_Left_180.ani", -180, 17, false, true));
    }

    void Update(float dt)
    {
        if (motions[selectIndex].Move(dt, ownner.sceneNode, ownner.animCtrl))
        {
            if (gInput.IsLeftStickInDeadZone() && gInput.HasLeftStickBeenStationary(0.1))
                ownner.stateMachine.ChangeState("StandState");
            else {
                ownner.animCtrl.SetSpeed(motions[selectIndex].name, 1);
                ownner.stateMachine.ChangeState("MoveState");
            }
        }
    }

    int PickIndex()
    {
        return ownner.sceneNode.vars["AnimationIndex"].GetInt() - 1;
    }
};

class PlayerMoveState : CharacterState
{
    Motion@ motion;
    float fullTurnThreashold;
    float turnSpeed;

    PlayerMoveState(Character@ c)
    {
        super(c);
        name = "MoveState";
        @motion = Motion("Animation/Walk_Forward.ani", 0, -1, true, false);
        fullTurnThreashold = 115;
        turnSpeed = 5;
    }

    void Update(float dt)
    {
        // check if we should return to the idle state
        if (gInput.IsLeftStickInDeadZone() && gInput.HasLeftStickBeenStationary(0.1))
            ownner.stateMachine.ChangeState("StandState");

        // compute the difference between the direction the character is facing
        // and the direction the user wants to go in
        float characterDifference = ComputeDifference_Player(ownner.sceneNode)  ;

        // if the difference is greater than this about, turn the character
        ownner.sceneNode.Yaw(characterDifference * turnSpeed * dt);
        motion.Move(dt, ownner.sceneNode, ownner.animCtrl);

        bool evade = gInput.IsEvadePressed();

        // if the difference is large, then turn 180 degrees
        if ( (Abs(characterDifference) > fullTurnThreashold) && gInput.IsLeftStickStationary() )
        {
            Print("180!!!");
            if (evade) {
                ownner.sceneNode.vars["AnimationIndex"] = 1;
                ownner.stateMachine.ChangeState("EvadeState");
            }
            else
                ownner.stateMachine.ChangeState("MoveTurn180State");
        }

        if(evade) {
            ownner.sceneNode.vars["AnimationIndex"] = 0;
            ownner.stateMachine.ChangeState("EvadeState");
        }
    }

    void Enter(State@ lastState)
    {
        PlayerStandToMoveState@ standToMoveState = cast<PlayerStandToMoveState@>(lastState);
        motion.Start(ownner.sceneNode, ownner.animCtrl, 0.0, 0.2);
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        motion.DebugDraw(debug, ownner.sceneNode);
    }
};

class PlayerMoveTurn180State : CharacterState
{
    Motion@ motion;

    PlayerMoveTurn180State(Character@ c)
    {
        super(c);
        name = "MoveTurn180State";
        @motion = Motion("Animation/Turn_Right_180.ani", 180, 22, false, true, 1.0);
    }

    void Update(float dt)
    {
        if (motion.Move(dt, ownner.sceneNode, ownner.animCtrl))
            ownner.CommonStateFinishedOnGroud();
    }

    void Enter(State@ lastState)
    {
        motion.Start(ownner.sceneNode, ownner.animCtrl, 0.0f, 0.1f);
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        motion.DebugDraw(debug, ownner.sceneNode);
    }
};

class PlayerAttackState : MultiMotionState
{
    PlayerAttackState(Character@ c)
    {
        super(c);
        name = "AttackState";
        motions.Push(Motion("Animation/Attack_Close_Forward_07.ani", 0, -1, false, false));
        motions.Push(Motion("Animation/Attack_Close_Forward_08.ani", 0, -1, false, false));
    }

    void Update(float dt)
    {
        if (motions[selectIndex].Move(dt, ownner.sceneNode, ownner.animCtrl))
            ownner.stateMachine.ChangeState("StandState");
    }

    void Enter(State@ lastState)
    {
        // Find the best enemy
        Vector3 camDir = cameraNode.worldRotation * Vector3(0, 0, 1);
        float cameraAngle = Atan2(camDir.x, camDir.z);
        float targetAngle = gInput.m_leftStickAngle + cameraAngle;
        gEnemyMgr.scoreCache.Clear();

        Print("Attack targetAngle=" + String(targetAngle));

        Vector3 myPos = ownner.sceneNode.worldPosition;
        for (uint i=0; i<gEnemyMgr.enemyList.length; ++i)
        {
            Enemy@ e = gEnemyMgr.enemyList[i];
            Vector3 posDiff = e.sceneNode.worldPosition - myPos;
            posDiff.y = 0;
            int enemyScroe = 100;

            float distSQR = posDiff.lengthSquared;
            float diffAngle = Atan2(posDiff.x, posDiff.z);
            Print("Enemy distSQR=" + String(distSQR) + " diffAngle=" + String(diffAngle));
        }

        MultiMotionState::Enter(lastState);
    }

    int PickIndex()
    {
        return RandomInt(motions.length);
    }
};


class PlayerEvadeState : MultiMotionState
{
    PlayerEvadeState(Character@ c)
    {
        super(c);
        name = "EvadeState";
        motions.Push(Motion("Animation/Evade_Forward_01.ani", 0, -1, false, false));
        motions.Push(Motion("Animation/Evade_Back_01.ani", 0, -1, false, false));
    }

    void Update(float dt)
    {
        if (motions[selectIndex].Move(dt, ownner.sceneNode, ownner.animCtrl))
            ownner.CommonStateFinishedOnGroud();
    }

    int PickIndex()
    {
        return ownner.sceneNode.vars["AnimationIndex"].GetInt();
    }
};

class PlayerAlignState : CharacterAlignState
{
    PlayerAlignState(Character@ c)
    {
        super(c);
    }
};

class PlayerCounterState : MultiMotionState
{
    PlayerCounterState(Character@ c)
    {
        super(c);
        name = "CounterState";
        motions.Push(Motion("Animation/Counter_Arm_Front_01.ani", 0, -1, false, false));
    }

    void Update(float dt)
    {
        if (motions[selectIndex].Move(dt, ownner.sceneNode, ownner.animCtrl))
            ownner.stateMachine.ChangeState("StandState");
    }

    int PickIndex()
    {
        return ownner.sceneNode.vars["CounterIndex"].GetInt();
    }
};

class Player : Character
{
    int maxAttackDistSQR;
    int combo;

    Player()
    {
        super();
        combo = 0;
        maxAttackDistSQR = 10.f * 10.0f;
    }

    void Start()
    {
        Character::Start();
        stateMachine.AddState(PlayerStandState(this));
        stateMachine.AddState(PlayerStandToMoveState(this));
        stateMachine.AddState(PlayerMoveState(this));
        stateMachine.AddState(PlayerMoveTurn180State(this));
        stateMachine.AddState(PlayerAttackState(this));
        stateMachine.AddState(PlayerAlignState(this));
        stateMachine.AddState(PlayerCounterState(this));
        stateMachine.AddState(PlayerEvadeState(this));
        stateMachine.ChangeState("StandState");
    }

    void Update(float dt)
    {
        // Print("Player::Update " + String(dt));
        Character::Update(dt);
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        debug.AddNode(sceneNode, 1.0f, false);
        debug.AddNode(sceneNode.GetChild("Bip01", true), 1.0f, false);
        Vector3 fwd = Vector3(0, 0, 1);
        Vector3 camDir = cameraNode.worldRotation * fwd;
        float cameraAngle = Atan2(camDir.x, camDir.z);
        Vector3 characterDir = sceneNode.worldRotation * fwd;
        float characterAngle = Atan2(characterDir.x, characterDir.z);
        float targetAngle = cameraAngle + gInput.m_leftStickAngle;
        float baseLen = 2.0f;
        DebugDrawDirection(debug, sceneNode, targetAngle, Color(1, 1, 0), baseLen);
        DebugDrawDirection(debug, sceneNode, characterAngle, Color(1, 0, 1), baseLen);
    }

    void Attack()
    {
        stateMachine.ChangeState("AttackState");
    }

    void Counter()
    {
        Counter(thug, 0, 0.2f); // just for test now
    }

    void Counter(Character@ other, int index, float t)
    {
        if (stateMachine.currentState.name == "CounterState" ||
            stateMachine.currentState.name == "AlignState")
        {
            Print(sceneNode.name + " already in counter|align state!");
            return;
        }

        if (other.stateMachine.currentState.name == "CounterState")
        {
            Print(other.sceneNode.name + " already in counter state!");
            return;
        }

        Print("Counter " + other.sceneNode.name + " index=" + String(index));
        CharacterState@ thisState = cast<CharacterState@>(stateMachine.FindState("CounterState"));
        CharacterState@ otherState = cast<CharacterState@>(stateMachine.FindState("CounterState"));
        Vector3 pos1 = thisState.GetMotion(index).startFromOrigin;
        Vector3 pos2 = otherState.GetMotion(index).startFromOrigin;
        sceneNode.vars["CounterIndex"] = index;
        other.sceneNode.vars["CounterIndex"] = index;
        float yawDiff = 180; // will change for later back counter
        LineUpdateWithObject(other.sceneNode, "CounterState", yawDiff, pos1 + pos2, t);
    }

    String GetDebugText()
    {
        return Character::GetDebugText() +  "player combo=" + String(combo) + "\n";
    }

    void CommonStateFinishedOnGroud()
    {
        if (gInput.IsLeftStickInDeadZone() && gInput.HasLeftStickBeenStationary(0.1))
            stateMachine.ChangeState("StandState");
        else {
            stateMachine.ChangeState("MoveState");
        }
    }
};


// computes the difference between the characters current heading and the
// heading the user wants them to go in.
float ComputeDifference_Player(Node@ n)
{
    // if the user is not pushing the stick anywhere return.  this prevents the character from turning while stopping (which
    // looks bad - like the skid to stop animation)
    if( gInput.m_leftStickMagnitude < 0.5f )
        return 0;

    Vector3 camDir = cameraNode.worldRotation * Vector3(0, 0, 1);
    float cameraAngle = Atan2(camDir.x, camDir.z);
    // check the difference between the characters current heading and the desired heading from the gamepad
    return ComputeDifference(n, gInput.m_leftStickAngle + cameraAngle);
}

//  divides a circle into numSlices and returns the index (in clockwise order) of the slice which
//  contains the gamepad's angle relative to the camera.
int RadialSelectAnimation_Player(Node@ n, int numDirections)
{
    Vector3 camDir = cameraNode.worldRotation * Vector3(0, 0, 1);
    float cameraAngle = Atan2(camDir.x, camDir.z);
    return RadialSelectAnimation(n, numDirections, gInput.m_leftStickAngle + cameraAngle);
}