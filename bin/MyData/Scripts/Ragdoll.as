// CreateRagdoll script object class

enum RagdollBoneType
{
    BONE_HEAD,
    BONE_PELVIS,
    BONE_SPINE,
    BONE_L_THIGH,
    BONE_R_THIGH,
    BONE_L_CALF,
    BONE_R_CALF,
    BONE_L_UPPERARM,
    BONE_R_UPPERARM,
    BONE_L_FOREARM,
    BONE_R_FOREARM,
    BONE_L_HAND,
    BONE_R_HAND,
    BONE_L_FOOT,
    BONE_R_FOOT,
    RAGDOLL_BONE_NUM
};

enum RagdollState
{
    RAGDOLL_NONE,
    RAGDOLL_STATIC,
    RAGDOLL_DYNAMIC,
    RAGDOLL_BLEND_TO_ANIMATION,
};

const StringHash RAGDOLL_STATE("Ragdoll_State");
const StringHash RAGDOLL_PERPARE("Ragdoll_Prepare");
const StringHash RAGDOLL_START("Ragdoll_Start");
const StringHash RAGDOLL_STOP("Ragdoll_Stop");

bool test_ragdoll = false;

class Ragdoll : ScriptObject
{
    Array<Node@>      boneNodes;
    Array<Vector3>    boneLastPositions;
    Node@             rootNode;

    int               state;
    float             timeInState;

    // Animation@        blendingAnim;
    // float             ragdollToAnimBlendTime = 2.0f;

    float             minRagdollStateTime = 0.5f;

    Ragdoll()
    {
        state = RAGDOLL_NONE;
    }

    void Start()
    {
        Array<String> boneNames =
        {
            "Bip01_Head",
            "Bip01_Pelvis",//"Bip01_$AssimpFbx$_Translation",
            "Bip01_Spine1",
            "Bip01_L_Thigh",
            "Bip01_R_Thigh",
            "Bip01_L_Calf",
            "Bip01_R_Calf",
            "Bip01_L_UpperArm",
            "Bip01_R_UpperArm",
            "Bip01_L_Forearm",
            "Bip01_R_Forearm",
            "Bip01_L_Hand",
            "Bip01_R_Hand",
            "Bip01_L_Foot",
            "Bip01_R_Foot",
            // ----------------- end of ragdoll bone -------------------
            "Bip01_$AssimpFbx$_Translation",
            "Bip01_$AssimpFbx$_Rotation",
            "Bip01_$AssimpFbx$_PreRotation",
            "Bip01_Pelvis",
            "Bip01_Spine",
            "Bip01_Spine2",
            "Bip01_Spine3",
            "Bip01_Neck",
            "Bip01_L_Clavicle",
            "Bip01_R_Clavicle"
        };

        rootNode = node;
        boneNodes.Resize(boneNames.length);
        boneLastPositions.Resize(boneNames.length);

        for (uint i=0; i<RAGDOLL_BONE_NUM; ++i)
        {
            boneNodes[i] = node.GetChild(boneNames[i], true);
            boneLastPositions[i] = boneNodes[i].worldPosition;
        }

        Node@ renderNode = node;
        AnimatedModel@ model = node.GetComponent("AnimatedModel");
        if (model is null)
            renderNode = node.children[0];

        //blendingAnim = cache.GetResource("Animation", GetAnimationName("TG_Getup/GetUp_Back"));

        SubscribeToEvent(renderNode, "AnimationTrigger", "HandleAnimationTrigger");
    }

    void Stop()
    {
        boneNodes.Clear();
    }

    void ChangeState(int newState)
    {
        if (state == newState)
            return;

        int old_state = state;
        Print("Ragdoll ChangeState from " + old_state + " to " + newState);
        state = newState;

        if (newState == RAGDOLL_STATIC)
        {
            for (uint i=0; i<RAGDOLL_BONE_NUM; ++i)
            {
                boneLastPositions[i] = boneNodes[i].worldPosition;
            }
        }
        else if (newState == RAGDOLL_DYNAMIC)
        {
            SetAnimationEnabled(false);
            CreateRagdoll();

            if (timeInState > 0.1f)
            {
                for (uint i=0; i<RAGDOLL_BONE_NUM; ++i)
                {
                    RigidBody@ rb = boneNodes[i].GetComponent("RigidBody");
                    if (rb !is null)
                    {
                        Vector3 velocity = boneNodes[i].worldPosition - boneLastPositions[i];
                        float scale = rootNode.vars[TIME_SCALE].GetFloat();
                        velocity /= timeInState;
                        velocity *= scale;
                        Print(boneNodes[i].name + " velocity=" + velocity.ToString());
                        // if (i == BONE_PELVIS || i == BONE_SPINE)
                        rb.linearVelocity = velocity;
                    }
                }
            }
        }
        else if (newState == RAGDOLL_BLEND_TO_ANIMATION) {
            DestroyRagdoll();
            SetAnimationEnabled(true);
            ResetBonePositions();
        }
        else if (newState == RAGDOLL_NONE)
        {
            DestroyRagdoll();
            SetAnimationEnabled(true);
            ResetBonePositions();
        }

        rootNode.vars[RAGDOLL_STATE] = newState;
        timeInState = 0.0f;
    }

    void CreateRagdoll()
    {
        uint t = time.systemTime;

        // Create RigidBody & CollisionShape components to bones
        Quaternion identityQ(0, 0, 0);
        Quaternion common_rotation(0, 0, 90); // model exported from 3DS MAX need to roll 90

        Vector3 upper_leg_size(0.2f, 0.45f, 0.2f);
        Vector3 uppper_leg_offset(0.3f, 0.0f, 0.0f);

        Vector3 lower_leg_size(0.175f, 0.55f, 0.175f);
        Vector3 lower_leg_offset(0.25f, 0.0f, 0.0f);

        Vector3 upper_arm_size(0.15f, 0.4f, 0.175f);
        Vector3 upper_arm_offset_left(0.1f, 0.0f, 0.01f);
        Vector3 upper_arm_offset_right(0.1f, 0.0f, -0.01f);

        Vector3 lower_arm_size(0.15f, 0.35f, 0.15f);
        Vector3 lower_arm_offset_left(0.125f, 0.0f, 0.01f);
        Vector3 lower_arm_offset_right(0.125f, 0.0f, -0.01f);

        CreateRagdollBone(boneNodes[BONE_PELVIS], SHAPE_BOX, Vector3(0.3f, 0.2f, 0.25f), Vector3(0.0f, 0.0f, 0.0f), identityQ);
        CreateRagdollBone(boneNodes[BONE_SPINE], SHAPE_BOX, Vector3(0.35f, 0.2f, 0.3f), Vector3(0.15f, 0.0f, 0.0f), identityQ);
        CreateRagdollBone(boneNodes[BONE_HEAD], SHAPE_BOX, Vector3(0.275f, 0.2f, 0.25f), Vector3(0.0f, 0.0f, 0.0f), identityQ);


        CreateRagdollBone(boneNodes[BONE_L_THIGH], SHAPE_CAPSULE, upper_leg_size, uppper_leg_offset, common_rotation);
        CreateRagdollBone(boneNodes[BONE_R_THIGH], SHAPE_CAPSULE, upper_leg_size, uppper_leg_offset, common_rotation);

        CreateRagdollBone(boneNodes[BONE_L_CALF], SHAPE_CAPSULE, lower_leg_size, lower_leg_offset, common_rotation);
        CreateRagdollBone(boneNodes[BONE_R_CALF], SHAPE_CAPSULE, lower_leg_size, lower_leg_offset, common_rotation);

        CreateRagdollBone(boneNodes[BONE_L_UPPERARM], SHAPE_CAPSULE, upper_arm_size, upper_arm_offset_left, common_rotation);
        CreateRagdollBone(boneNodes[BONE_R_UPPERARM], SHAPE_CAPSULE, upper_arm_size, upper_arm_offset_right, common_rotation);

        CreateRagdollBone(boneNodes[BONE_L_FOREARM], SHAPE_CAPSULE, lower_arm_size, lower_arm_offset_left, common_rotation);
        CreateRagdollBone(boneNodes[BONE_R_FOREARM], SHAPE_CAPSULE, lower_arm_size, lower_arm_offset_right, common_rotation);

        // Create Constraints between bones
        CreateRagdollConstraint(boneNodes[BONE_HEAD], boneNodes[BONE_SPINE], CONSTRAINT_CONETWIST,
            Vector3(-1.0f, 0.0f, 0.0f), Vector3(-1.0f, 0.0f, 0.0f), Vector2(0.0f, 30.0f), Vector2(0.0f, 0.0f));

        CreateRagdollConstraint(boneNodes[BONE_L_THIGH], boneNodes[BONE_PELVIS], CONSTRAINT_CONETWIST, Vector3(0.0f, 0.0f, -1.0f),
            Vector3(0.0f, 0.0f, 1.0f), Vector2(45.0f, 45.0f), Vector2(0.0f, 0.0f));
        CreateRagdollConstraint(boneNodes[BONE_R_THIGH], boneNodes[BONE_PELVIS], CONSTRAINT_CONETWIST, Vector3(0.0f, 0.0f, -1.0f),
            Vector3(0.0f, 0.0f, 1.0f), Vector2(45.0f, 45.0f), Vector2(0.0f, 0.0f));
        CreateRagdollConstraint(boneNodes[BONE_L_CALF], boneNodes[BONE_L_THIGH], CONSTRAINT_HINGE, Vector3(0.0f, 0.0f, -1.0f),
            Vector3(0.0f, 0.0f, -1.0f), Vector2(90.0f, 0.0f), Vector2(0.0f, 0.0f));
        CreateRagdollConstraint(boneNodes[BONE_R_CALF], boneNodes[BONE_R_THIGH], CONSTRAINT_HINGE, Vector3(0.0f, 0.0f, -1.0f),
            Vector3(0.0f, 0.0f, -1.0f), Vector2(90.0f, 0.0f), Vector2(0.0f, 0.0f));
        CreateRagdollConstraint(boneNodes[BONE_SPINE], boneNodes[BONE_PELVIS], CONSTRAINT_HINGE, Vector3(0.0f, 0.0f, 1.0f),
            Vector3(0.0f, 0.0f, 1.0f), Vector2(45.0f, 0.0f), Vector2(-10.0f, 0.0f));
        CreateRagdollConstraint(boneNodes[BONE_L_UPPERARM], boneNodes[BONE_SPINE], CONSTRAINT_CONETWIST, Vector3(0.0f, -1.0f, 0.0f),
            Vector3(0.0f, 1.0f, 0.0f), Vector2(45.0f, 45.0f), Vector2(0.0f, 0.0f), false);
        CreateRagdollConstraint(boneNodes[BONE_R_UPPERARM], boneNodes[BONE_SPINE], CONSTRAINT_CONETWIST, Vector3(0.0f, -1.0f, 0.0f),
            Vector3(0.0f, 1.0f, 0.0f), Vector2(45.0f, 45.0f), Vector2(0.0f, 0.0f), false);
        CreateRagdollConstraint(boneNodes[BONE_L_FOREARM], boneNodes[BONE_L_UPPERARM], CONSTRAINT_HINGE, Vector3(0.0f, 0.0f, -1.0f),
            Vector3(0.0f, 0.0f, -1.0f), Vector2(90.0f, 0.0f), Vector2(0.0f, 0.0f));
        CreateRagdollConstraint(boneNodes[BONE_R_FOREARM], boneNodes[BONE_R_UPPERARM], CONSTRAINT_HINGE, Vector3(0.0f, 0.0f, -1.0f),
            Vector3(0.0f, 0.0f, -1.0f), Vector2(90.0f, 0.0f), Vector2(0.0f, 0.0f));

        Print("CreateRagdoll time-cost=" + (time.systemTime - t) + " ms");
    }

    void CreateRagdollBone(Node@ boneNode, ShapeType type, const Vector3&in size, const Vector3&in position, const Quaternion&in rotation, float scale = 100)
    {
        RigidBody@ body = boneNode.CreateComponent("RigidBody");
        // Set mass to make movable
        body.mass = 1.0f;
        // Set damping parameters to smooth out the motion
        body.linearDamping = 0.075f;
        body.angularDamping = 0.85f;
        // Set rest thresholds to ensure the ragdoll rigid bodies come to rest to not consume CPU endlessly
        body.linearRestThreshold = 2.5f;
        body.angularRestThreshold = 1.5;
        body.collisionLayer = COLLISION_LAYER_RAGDOLL;
        body.collisionMask = COLLISION_LAYER_RAGDOLL | COLLISION_LAYER_PROP | COLLISION_LAYER_LANDSCAPE;
        body.friction = 0.75f;
        //body.kinematic = true;

        CollisionShape@ shape = boneNode.CreateComponent("CollisionShape");
        // We use either a box or a capsule shape for all of the bones
        if (type == SHAPE_BOX)
            shape.SetBox(size * scale, position * scale, rotation);
        else if (type == SHAPE_SPHERE)
            shape.SetSphere(size.x * scale, position * scale, rotation);
        else
            shape.SetCapsule(size.x * scale, size.y * scale, position * scale, rotation);
    }

    void CreateRagdollConstraint(Node@ boneNode, Node@ parentNode, ConstraintType type,
        const Vector3&in axis, const Vector3&in parentAxis, const Vector2&in highLimit, const Vector2&in lowLimit,
        bool disableCollision = true)
    {
        Constraint@ constraint = boneNode.CreateComponent("Constraint");
        constraint.constraintType = type;
        // Most of the constraints in the ragdoll will work better when the connected bodies don't collide against each other
        constraint.disableCollision = disableCollision;
        // The connected body must be specified before setting the world position
        constraint.otherBody = parentNode.GetComponent("RigidBody");
        // Position the constraint at the child bone we are connecting
        constraint.worldPosition = boneNode.worldPosition;
        // Configure axes and limits
        constraint.axis = axis;
        constraint.otherAxis = parentAxis;
        constraint.highLimit = highLimit;
        constraint.lowLimit = lowLimit;
    }

    void DestroyRagdoll()
    {
        for (uint i=0; i<RAGDOLL_BONE_NUM; ++i)
        {
            boneNodes[i].RemoveComponent("RigidBody");
            boneNodes[i].RemoveComponent("Constraint");
        }
    }

    void EnableRagdoll(bool bEnable)
    {
        for (uint i=0; i<RAGDOLL_BONE_NUM; ++i)
        {
            RigidBody@ rb = boneNodes[i].GetComponent("RigidBody");
            Constraint@ cs = boneNodes[i].GetComponent("Constraint");
            if (rb !is null)
                rb.enabled = bEnable;
            if (cs !is null)
                cs.enabled = bEnable;
        }
    }

    void FixedUpdate(float dt)
    {
        if (state == RAGDOLL_STATIC) {
            timeInState += dt;
        }
        else if (state == RAGDOLL_DYNAMIC) {

            timeInState += dt;

            uint num_of_freeze_objects = 0;
            for (uint i=0; i<RAGDOLL_BONE_NUM; ++i)
            {
                // Vector3 curPos = boneNodes[i].worldPosition;
                RigidBody@ rb = boneNodes[i].GetComponent("RigidBody");
                if (rb is null || !rb.active) {
                    num_of_freeze_objects ++;
                    continue;
                }

                Vector3 vel = rb.linearVelocity;
                if (vel.lengthSquared < 0.01f)
                    num_of_freeze_objects ++;
                //Print(boneNodes[i].name + " vel=" + vel.ToString());
            }

            // Print("num_of_freeze_objects=" + num_of_freeze_objects);
            if (num_of_freeze_objects == RAGDOLL_BONE_NUM && timeInState >= minRagdollStateTime)
                ChangeState(RAGDOLL_NONE);
        }
        /*else if (state == RAGDOLL_BLEND_TO_ANIMATION) {

            //compute the ragdoll blend amount in the range 0...1
            float ragdollBlendAmount = timeInState / ragdollToAnimBlendTime;
            ragdollBlendAmount = Clamp(ragdollBlendAmount, 0.0f, 1.0f);

            timeInState += dt;

            for (uint i=0; i<boneNodes.length; ++i)
            {
                AnimationTrack@ track = blendingAnim.tracks[boneNodes[i].name];
                if (track is null)
                    continue;

                Node@ n = boneNodes[i];
                Vector3 cur_position = n.position;
                Vector3 dst_position = track.keyFrames[0].position;

                Quaternion cur_rotation = n.rotation;
                Quaternion dst_rotation = track.keyFrames[0].rotation;

                // n.position = cur_position.Lerp(dst_position, ragdollBlendAmount);
                n.rotation = cur_rotation.Slerp(dst_rotation, ragdollBlendAmount);
            }

            //if the ragdoll blend amount has decreased to zero, move to animated state
            if (ragdollBlendAmount >= 0.9999999f)
                ChangeState(RAGDOLL_NONE);
        }*/
    }

    void SetAnimationEnabled(bool bEnable)
    {
        // Disable keyframe animation from all bones so that they will not interfere with the ragdoll
        AnimatedModel@ model = node.GetComponent("AnimatedModel");

        if (model is null)
            model = node.children[0].GetComponent("AnimatedModel");
        if (model is null)
            return;

        Skeleton@ skeleton = model.skeleton;
        for (uint i = 0; i < skeleton.numBones; ++i)
            skeleton.bones[i].animated = bEnable;

        if (!bEnable)
        {
            /*
            AnimationController@ ctl = model.node.GetComponent("AnimationController");
            if (ctl is null)
            {
                ctl.StopAll(0.0f);
            }
            */
            model.RemoveAllAnimationStates();
        }
    }

    void HandleAnimationTrigger(StringHash eventType, VariantMap& eventData)
    {
        StringHash data = eventData[DATA].GetStringHash();
        int new_state = RAGDOLL_NONE;
        if (data == RAGDOLL_PERPARE)
            new_state = RAGDOLL_STATIC;
        else if (data == RAGDOLL_START)
            new_state = RAGDOLL_DYNAMIC;
        else if (data == RAGDOLL_STOP) {
            //if (state == RAGDOLL_DYNAMIC)
            //    new_state = RAGDOLL_BLEND_TO_ANIMATION;
            //else
                new_state = RAGDOLL_NONE;
        }
        ChangeState(new_state);
    }

    void ResetBonePositions()
    {
        Quaternion oldRot = boneNodes[BONE_PELVIS].worldRotation;
        Vector3 pelvis_pos = boneNodes[BONE_PELVIS].worldPosition;

        Vector3 ragdolledDirection = rootNode.worldPosition - pelvis_pos;
        ragdolledDirection *= -1;
        ragdolledDirection.y = 0;
        Vector3 currentDirection = rootNode.worldRotation * Vector3(0, 0, 1);
        currentDirection.y = 0.0f;

        boneNodes[BONE_PELVIS].position = Vector3(0, 0, 0);
        Node@ t_node = rootNode.GetChild("Bip01_$AssimpFbx$_Translation", true);
        Node@ r_node = rootNode.GetChild("Bip01_$AssimpFbx$_Rotation", true);
        Vector3 cur_root_pos = rootNode.worldPosition;
        Vector3 dest_root_pos = cur_root_pos;
        dest_root_pos.x = pelvis_pos.x;
        dest_root_pos.z = pelvis_pos.z;
        rootNode.worldPosition = dest_root_pos;
        t_node.worldPosition = pelvis_pos;

        Quaternion q;
        q.FromRotationTo(currentDirection, ragdolledDirection);
        rootNode.worldRotation *= q;
        // rootNode.worldRotation *= Quaternion(0, 180, 0);

        boneNodes[BONE_PELVIS].worldRotation = oldRot;

        //boneNodes[BONE_PELVIS].worldRotation = q.Inverse() * boneNodes[BONE_PELVIS].worldRotation;
        //boneNodes[BONE_PELVIS].rotation = Quaternion(90, 0, -90);
    }
}