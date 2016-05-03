
enum AttackStateType
{
    ATTACK_STATE_ALIGN,
    ATTACK_STATE_BEFORE_IMPACT,
    ATTACK_STATE_AFTER_IMPACT,
};

class PlayerAttackState : CharacterState
{
    Array<AttackMotion@>    forwardAttacks;
    Array<AttackMotion@>    leftAttacks;
    Array<AttackMotion@>    rightAttacks;
    Array<AttackMotion@>    backAttacks;

    AttackMotion@           currentAttack;

    int                     state;
    Vector3                 movePerSec;
    Vector3                 predictPosition;
    Vector3                 motionPosition;

    float                   alignTime = 0.2f;

    int                     forwadCloseNum = 0;
    int                     leftCloseNum = 0;
    int                     rightCloseNum = 0;
    int                     backCloseNum = 0;

    int                     slowMotionFrames = 2;

    int                     lastAttackDirection = -1;
    int                     lastAttackIndex = -1;

    bool                    weakAttack = true;
    bool                    slowMotion = false;
    bool                    lastKill = false;

    PlayerAttackState(Character@ c)
    {
        super(c);
        SetName("AttackState");
        flags = FLAGS_ATTACK;
    }

    void DumpAttacks(Array<AttackMotion@>@ attacks)
    {
        for (uint i=0; i<attacks.length; ++i)
        {
            Motion@ m = attacks[i].motion;
            if (m !is null)
                Print(m.animationName + " impactDist=" + String(attacks[i].impactDist));
        }
    }

    float UpdateMaxDist(Array<AttackMotion@>@ attacks, float dist)
    {
        if (attacks.empty)
            return dist;

        float maxDist = attacks[attacks.length-1].motion.endDistance;
        return (maxDist > dist) ? maxDist : dist;
    }

    void Dump()
    {
        Print("\n forward attacks(closeNum=" + forwadCloseNum + "): \n");
        DumpAttacks(forwardAttacks);
        Print("\n right attacks(closeNum=" + rightCloseNum + "): \n");
        DumpAttacks(rightAttacks);
        Print("\n back attacks(closeNum=" + backCloseNum + "): \n");
        DumpAttacks(backAttacks);
        Print("\n left attacks(closeNum=" + leftCloseNum + "): \n");
        DumpAttacks(leftAttacks);
    }

    ~PlayerAttackState()
    {
        @currentAttack = null;
    }

    void ChangeSubState(int newState)
    {
        Print("PlayerAttackState changeSubState from " + state + " to " + newState);
        state = newState;
    }

    void Update(float dt)
    {
        Motion@ motion = currentAttack.motion;

        Node@ _node = ownner.GetNode();
        Node@ tailNode = _node.GetChild("TailNode", true);
        Node@ attackNode = _node.GetChild(currentAttack.boneName, true);

        if (tailNode !is null && attackNode !is null) {
            tailNode.worldPosition = attackNode.worldPosition;
        }

        ownner.motion_velocity = (state == ATTACK_STATE_ALIGN) ? movePerSec : Vector3(0, 0, 0);

        float t = ownner.animCtrl.GetTime(motion.animationName);
        if (state == ATTACK_STATE_ALIGN)
        {
            if (t >= alignTime)
            {
                ChangeSubState(ATTACK_STATE_BEFORE_IMPACT);
                ownner.target.RemoveFlag(FLAGS_NO_MOVE);
            }
        }
        else if (state == ATTACK_STATE_BEFORE_IMPACT)
        {
            if (t > currentAttack.impactTime)
            {
                ChangeSubState(ATTACK_STATE_AFTER_IMPACT);
                AttackImpact();
            }
        }

        if (slowMotion)
        {
            float t_diff = currentAttack.impactTime - t;
            if (t_diff > 0 && t_diff < SEC_PER_FRAME * slowMotionFrames)
                ownner.SetSceneTimeScale(0.1f);
            else
                ownner.SetSceneTimeScale(1.0f);
        }

        ownner.CheckTargetDistance(ownner.target, PLAYER_COLLISION_DIST);

        bool finished = motion.Move(ownner, dt) == 1;
        if (finished) {
            Print("Player::Attack finish attack movemont in sub state = " + state);
            ownner.CommonStateFinishedOnGroud();
            return;
        }

        CheckInput(t);
        CharacterState::Update(dt);
    }


    void CheckInput(float t)
    {
        if (ownner.IsInAir())
            return;

        int addition_frames = slowMotion ? slowMotionFrames : 0;
        bool check_attack = t > currentAttack.impactTime + SEC_PER_FRAME * ( HIT_WAIT_FRAMES + 1 + addition_frames);
        bool check_others = t > currentAttack.impactTime + SEC_PER_FRAME * addition_frames;
        ownner.ActionCheck(check_attack, check_others, check_others);
    }

    void PickBestMotion(Array<AttackMotion@>@ attacks, int dir)
    {
        Vector3 myPos = ownner.GetNode().worldPosition;
        Vector3 enemyPos = ownner.target.GetNode().worldPosition;
        Vector3 diff = enemyPos - myPos;
        diff.y = 0;
        float toEnenmyDistance = diff.length - PLAYER_COLLISION_DIST;
        if (toEnenmyDistance < 0.0f)
            toEnenmyDistance = 0.0f;
        int bestIndex = 0;
        diff.Normalize();

        int index_start = -1;
        int index_num = 0;

        float min_dist = Max(0.0f, toEnenmyDistance - ATTACK_DIST_PICK_RANGE/2.0f);
        float max_dist = toEnenmyDistance + ATTACK_DIST_PICK_RANGE;
        Print("Player attack toEnenmyDistance = " + toEnenmyDistance + "(" + min_dist + "," + max_dist + ")");

        for (uint i=0; i<attacks.length; ++i)
        {
            AttackMotion@ am = attacks[i];
            // Print("am.impactDist=" + am.impactDist);
            if (am.impactDist > max_dist)
                break;

            if (am.impactDist > min_dist)
            {
                if (index_start == -1)
                    index_start = i;
                index_num ++;
            }
        }

        if (index_num == 0)
        {
            if (toEnenmyDistance > attacks[attacks.length - 1].impactDist)
                bestIndex = attacks.length - 1;
            else
                bestIndex = 0;
        }
        else
        {
            int r_n = RandomInt(index_num);
            bestIndex = index_start + r_n % index_num;
            if (lastAttackDirection == dir && bestIndex == lastAttackIndex)
            {
                Print("Repeat Attack index index_num=" + index_num);
                bestIndex = index_start + (r_n + 1) % index_num;
            }
            lastAttackDirection = dir;
            lastAttackIndex = bestIndex;
        }

        Print("Attack bestIndex="+bestIndex+" index_start="+index_start+" index_num="+index_num);

        @currentAttack = attacks[bestIndex];
        alignTime = currentAttack.impactTime;

        predictPosition = myPos + diff * toEnenmyDistance;
        Print("PlayerAttack dir=" + lastAttackDirection + " index=" + lastAttackIndex + " Pick attack motion = " + currentAttack.motion.animationName);
    }

    void StartAttack()
    {
        Player@ p = cast<Player>(ownner);
        if (ownner.target !is null)
        {
            state = ATTACK_STATE_ALIGN;
            float diff = ownner.ComputeAngleDiff(ownner.target.GetNode());
            int r = DirectionMapToIndex(diff, 4);

            if (d_log)
                Print("Attack-align " + " r-index=" + r + " diff=" + diff);

            if (r == 0)
                PickBestMotion(forwardAttacks, r);
            else if (r == 1)
                PickBestMotion(rightAttacks, r);
            else if (r == 2)
                PickBestMotion(backAttacks, r);
            else if (r == 3)
                PickBestMotion(leftAttacks, r);

            ownner.target.RequestDoNotMove();
            p.lastAttackId = ownner.target.GetNode().id;
        }
        else
        {
            int index = ownner.RadialSelectAnimation(4);
            if (index == 0)
                currentAttack = forwardAttacks[RandomInt(forwadCloseNum)];
            else if (index == 1)
                currentAttack = rightAttacks[RandomInt(rightCloseNum)];
            else if (index == 2)
                currentAttack = backAttacks[RandomInt(backCloseNum)];
            else if (index == 3)
                currentAttack = leftAttacks[RandomInt(leftCloseNum)];
            state = ATTACK_STATE_BEFORE_IMPACT;
            p.lastAttackId = M_MAX_UNSIGNED;

            // lost combo
            p.combo = 0;
            p.StatusChanged();
        }

        Motion@ motion = currentAttack.motion;
        motion.Start(ownner);
        weakAttack = cast<Player>(ownner).combo < MAX_WEAK_ATTACK_COMBO;
        slowMotion = (p.combo >= 3) ? (RandomInt(10) == 1) : false;

        if (ownner.target !is null)
        {
            motionPosition = motion.GetFuturePosition(ownner, currentAttack.impactTime);
            movePerSec = ( predictPosition - motionPosition ) / alignTime;
            movePerSec.y = 0;

            //if (attackEnemy.HasFlag(FLAGS_COUNTER))
            //    slowMotion = true;

            lastKill = p.CheckLastKill();
        }
        else
        {
            weakAttack = false;
            slowMotion = false;
        }

        if (lastKill)
        {
            ownner.SetSceneTimeScale(LAST_KILL_SPEED);
            weakAttack = false;
            slowMotion = false;
        }

        ownner.SetNodeEnabled("TailNode", true);
    }

    void Enter(State@ lastState)
    {
        Print("################## Player::AttackState Enter from " + lastState.name  + " #####################");
        lastKill = false;
        slowMotion = false;
        @currentAttack = null;
        state = ATTACK_STATE_ALIGN;
        movePerSec = Vector3(0, 0, 0);
        StartAttack();
        //ownner.SetSceneTimeScale(0.25f);
        //ownner.SetTimeScale(1.5f);
        CharacterState::Enter(lastState);
    }

    void Exit(State@ nextState)
    {
        CharacterState::Exit(nextState);
        ownner.SetNodeEnabled("TailNode", false);
        //if (nextState !is this)
        //    cast<Player>(ownner).lastAttackId = M_MAX_UNSIGNED;
        if (ownner.target !is null)
            ownner.target.RemoveFlag(FLAGS_NO_MOVE);
        @currentAttack = null;
        ownner.SetSceneTimeScale(1.0f);
        Print("################## Player::AttackState Exit to " + nextState.name  + " #####################");
    }

    void DebugDraw(DebugRenderer@ debug)
    {
        if (currentAttack is null || ownner.target is null)
            return;
        debug.AddLine(ownner.GetNode().worldPosition, ownner.target.GetNode().worldPosition, RED, false);
        debug.AddCross(predictPosition, 0.5f, Color(0.25f, 0.28f, 0.7f), false);
        debug.AddCross(motionPosition, 0.5f, Color(0.75f, 0.28f, 0.27f), false);
    }

    String GetDebugText()
    {
        return " name=" + name + " timeInState=" + String(timeInState) + "\n" +
                "currentAttack=" + currentAttack.motion.animationName +
                " weakAttack=" + weakAttack +
                " slowMotion=" + slowMotion +
                "\n";
    }

    bool CanReEntered()
    {
        return true;
    }

    void AttackImpact()
    {
        Character@ e = ownner.target;

        if (e is null)
            return;

        Node@ _node = ownner.GetNode();
        Vector3 dir = _node.worldPosition - e.GetNode().worldPosition;
        dir.y = 0;
        dir.Normalize();
        Print("PlayerAttackState::" +  e.GetName() + " OnDamage!!!!");

        Node@ n = _node.GetChild(currentAttack.boneName, true);
        Vector3 position = _node.worldPosition;
        if (n !is null)
            position = n.worldPosition;

        int damage = ownner.attackDamage;
        if (lastKill)
            damage = 9999;
        else
            damage = RandomInt(ownner.attackDamage, ownner.attackDamage + 20);
        bool b = e.OnDamage(ownner, position, dir, damage, weakAttack);
        if (!b)
            return;

        ownner.SpawnParticleEffect(position, "Particle/SnowExplosion.xml", 5.0f, 5.0f);
        ownner.SpawnParticleEffect(position, "Particle/HitSpark.xml", 1.0f, 0.6f);

        int sound_type = e.health == 0 ? 1 : 0;
        ownner.PlayRandomSound(sound_type);
        ownner.OnAttackSuccess(e);
    }

    void PostInit(float closeDist = 2.5f)
    {
        forwardAttacks.Sort();
        leftAttacks.Sort();
        rightAttacks.Sort();
        backAttacks.Sort();

        float dist = 0.0f;
        dist = UpdateMaxDist(forwardAttacks, dist);
        dist = UpdateMaxDist(leftAttacks, dist);
        dist = UpdateMaxDist(rightAttacks, dist);
        dist = UpdateMaxDist(backAttacks, dist);

        Print(ownner.GetName() + " max attack dist = " + dist);
        dist += 10.0f;
        MAX_ATTACK_DIST = Min(MAX_ATTACK_DIST, dist);

        for (uint i=0; i<forwardAttacks.length; ++i)
        {
            if (forwardAttacks[i].impactDist >= closeDist)
                break;
            forwadCloseNum++;
        }
        for (uint i=0; i<rightAttacks.length; ++i)
        {
            if (rightAttacks[i].impactDist >= closeDist)
                break;
            rightCloseNum++;
        }
        for (uint i=0; i<backAttacks.length; ++i)
        {
            if (backAttacks[i].impactDist >= closeDist)
                break;
            backCloseNum++;
        }
        for (uint i=0; i<leftAttacks.length; ++i)
        {
            if (leftAttacks[i].impactDist >= closeDist)
                break;
            leftCloseNum++;
        }

        if (d_log)
            Dump();
    }
};


class PlayerCounterState : CharacterCounterState
{
    Enemy@          counterEnemy;
    Array<int>      intCache;

    int             lastCounterIndex = -1;
    int             lastCounterDirection = -1;

    PlayerCounterState(Character@ c)
    {
        super(c);
        intCache.Reserve(50);
    }

    void Update(float dt)
    {
        if (counterEnemy is null || currentMotion is null)
        {
            ownner.CommonStateFinishedOnGroud(); // Something Error Happened
            return;
        }
        if (state == COUNTER_WAITING)
        {
            if (counterEnemy.GetState().nameHash == this.nameHash)
                StartAnimating();
        }
        CharacterCounterState::Update(dt);
    }

    void Enter(State@ lastState)
    {
        Print("############# PlayerCounterState::Enter ##################");
        uint t = time.systemTime;

        if (lastState.nameHash == ALIGN_STATE)
        {
            StartAnimating();
        }
        else
        {
            Node@ myNode = ownner.GetNode();
            Vector3 myPos = myNode.worldPosition;

            Enemy@ e = counterEnemy;
            Node@ eNode = e.GetNode();
            float dAngle = ownner.ComputeAngleDiff(eNode);
            bool isBack = false;
            if (Abs(dAngle) > 90)
                isBack = true;

            e.ChangeState("CounterState");

            int attackType = eNode.vars[ATTACK_TYPE].GetInt();
            CharacterCounterState@ s = cast<CharacterCounterState>(e.GetState());
            Array<Motion@>@ counterMotions = GetCounterMotions(attackType, isBack);
            Array<Motion@>@ eCounterMotions = s.GetCounterMotions(attackType, isBack);

            intCache.Clear();
            float maxDistSQR = COUNTER_ALIGN_MAX_DIST * COUNTER_ALIGN_MAX_DIST;
            float bestDistSQR = 999999;
            int bestIndex = -1;

            for (uint i=0; i<counterMotions.length; ++i)
            {
                Motion@ alignMotion = counterMotions[i];
                Motion@ baseMotion = eCounterMotions[i];
                Vector4 v4 = GetTargetTransform(eNode, alignMotion, baseMotion);
                Vector3 v3 = Vector3(v4.x, myPos.y, v4.z);
                float distSQR = (v3 - myPos).lengthSquared;
                if (distSQR < bestDistSQR)
                {
                    bestDistSQR = distSQR;
                    bestIndex = int(i);
                }
                if (distSQR > maxDistSQR)
                    continue;
                intCache.Push(i);
            }

            Print("CounterState - intCache.length=" + intCache.length);
            int cur_direction = GetCounterDirection(attackType, isBack);
            int idx;
            if (intCache.empty)
            {
                idx = bestIndex;
            }
            else
            {
                int k = RandomInt(intCache.length);
                idx = intCache[k];
                if (cur_direction == lastCounterDirection && idx == lastCounterIndex)
                {
                    k = (k + 1) % intCache.length;
                    idx = intCache[k];
                }
            }

            lastCounterDirection = cur_direction;
            lastCounterIndex = idx;

            @currentMotion = counterMotions[idx];
            @s.currentMotion = eCounterMotions[idx];
            Print("Counter-align angle-diff=" + dAngle + " isBack=" + isBack + " name:" + currentMotion.animationName);

            s.ChangeSubState(COUNTER_WAITING);

            Vector4 vt = GetTargetTransform(eNode, currentMotion, s.currentMotion);
            SetTargetTransform(Vector3(vt.x, myPos.y, vt.z), vt.w);
            StartAligning();
        }

        Print("PlayerCounterState::Enter time-cost=" + (time.systemTime - t));
        CharacterState::Enter(lastState);
    }

    void Exit(State@ nextState)
    {
        Print("############# PlayerCounterState::Exit ##################");
        CharacterCounterState::Exit(nextState);
        if (nextState !is this && nextState.nameHash != ALIGN_STATE)
            @counterEnemy = null;
    }

    void StartAnimating()
    {
        StartCounterMotion();
        if (counterEnemy !is null)
        {
            CharacterCounterState@ s = cast<CharacterCounterState>(counterEnemy.GetState());
            s.StartCounterMotion();
        }
    }

    void StartCounterMotion()
    {
        CharacterCounterState::StartCounterMotion();
        gCameraMgr.CheckCameraAnimation(currentMotion.name);
    }

    void OnAnimationTrigger(AnimationState@ animState, const VariantMap&in eventData)
    {
        StringHash name = eventData[NAME].GetStringHash();
        if (name == READY_TO_FIGHT)
            ownner.OnCounterSuccess();
        CharacterState::OnAnimationTrigger(animState, eventData);
    }

    bool CanReEntered()
    {
        return true;
    }
};

class PlayerHitState : MultiMotionState
{
    PlayerHitState(Character@ c)
    {
        super(c);
        SetName("HitState");
    }
};

class PlayerDeadState : MultiMotionState
{
    Array<String>   animations;
    int             state = 0;

    PlayerDeadState(Character@ c)
    {
        super(c);
        SetName("DeadState");
    }

    void Enter(State@ lastState)
    {
        state = 0;
        MultiMotionState::Enter(lastState);
    }

    void Update(float dt)
    {
        if (state == 0)
        {
            if (motions[selectIndex].Move(ownner, dt) == 1)
            {
                state = 1;
                gGame.OnCharacterKilled(null, ownner);
            }
        }
        CharacterState::Update(dt);
    }
};




