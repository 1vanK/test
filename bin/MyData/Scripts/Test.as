// ------------------------------------------------
#include "Scripts/Game.as"
#include "Scripts/AssetProcess.as"
#include "Scripts/Motion.as"
#include "Scripts/PhysicsDrag.as"
#include "Scripts/Input.as"
#include "Scripts/FSM.as"
#include "Scripts/Ragdoll.as"
#include "Scripts/Camera.as"
#include "Scripts/FadeOverlay.as"
#include "Scripts/Menu.as"
// ------------------------------------------------
#include "Scripts/GameObject.as"
#include "Scripts/Character.as"
#include "Scripts/Enemy.as"
#include "Scripts/Thug.as"
#include "Scripts/Player.as"

int drawDebug = 0;
bool autoCounter = false;
bool bHdr = true;
bool bigHeadMode = false;
bool nobgm = true;
bool has_redirect = false;
bool tonemapping = true;
int colorGradingIndex = 0;

Node@ musicNode;
float BGM_BASE_FREQ = 44100;

String CAMERA_NAME = "camera";
String PLAYER_NAME = "bruce"; //"bruce";

uint cameraId = M_MAX_UNSIGNED;
uint playerId = M_MAX_UNSIGNED;

int test_enemy_num_override = 9999;
bool lowend_platform = false;

void Start()
{
    Print("Game Running Platform: " + GetPlatform());
    lowend_platform = GetPlatform() != "Windows";

    Array<String>@ arguments = GetArguments();
    for (uint i = 0; i < arguments.length; ++i)
    {
        String argument = arguments[i].ToLower();
        if (argument[0] == '-')
        {
            argument = argument.Substring(1);
            if (argument == "nobgm")
            {
                nobgm = !nobgm;
            }
            else if (argument == "bighead")
            {
                bigHeadMode = !bigHeadMode;
            }
            else if (argument == "player")
            {
                PLAYER_NAME = arguments[i+1];
            }
            else if (argument == "lowend")
            {
                lowend_platform = true;
            }
            else if (argument == "hdr")
            {
                bHdr = !bHdr;
            }
            else if (argument == "tonemapping")
            {
                tonemapping = !tonemapping;
            }
        }
    }

    cache.autoReloadResources = true;
    engine.pauseMinimized = true;
    script.defaultScriptFile = scriptFile;
    if (renderer !is null)
        renderer.hdrRendering = bHdr;

    SetRandomSeed(time.systemTime);

    if (!engine.headless)
    {
        SetWindowTitleAndIcon();
        CreateConsoleAndDebugHud();
        CreateUI();
        InitAudio();
    }

    gGame.Start();
    gGame.ChangeState("LoadingState");

    SubscribeToEvents();
}

void Stop()
{
    Print("Test Stop");
    gMotionMgr.Stop();
    ui.Clear();
}

void InitAudio()
{
    if (engine.headless)
        return;

    audio.masterGain[SOUND_MASTER] = 0.5f;
    audio.masterGain[SOUND_MUSIC] = 0.5f;
    audio.masterGain[SOUND_EFFECT] = 1.0f;

    if (!nobgm)
    {
        Sound@ musicFile = cache.GetResource("Sound", "Sfx/bgm.ogg");
        musicFile.looped = true;

        BGM_BASE_FREQ = musicFile.frequency;

        // Note: the non-positional sound source component need to be attached to a node to become effective
        // Due to networked mode clearing the scene on connect, do not attach to the scene itself
        musicNode = Node();
        SoundSource@ musicSource = musicNode.CreateComponent("SoundSource");
        musicSource.soundType = SOUND_MUSIC;
        musicSource.gain = 0.5f;
        musicSource.Play(musicFile);
    }
}

void SetWindowTitleAndIcon()
{
    Image@ icon = cache.GetResource("Image", "Textures/UrhoIcon.png");
    graphics.windowIcon = icon;
}

void CreateConsoleAndDebugHud()
{
    // Get default style
    XMLFile@ xmlFile = cache.GetResource("XMLFile", "UI/DefaultStyle.xml");
    if (xmlFile is null)
        return;

    // Create console
    Console@ console = engine.CreateConsole();
    console.defaultStyle = xmlFile;
    console.background.opacity = 0.8f;

    // Create debug HUD
    DebugHud@ debugHud = engine.CreateDebugHud();
    debugHud.defaultStyle = xmlFile;
}

void SetLogoVisible(bool enable)
{
    Sprite@ logoSprite = ui.root.GetChild("logo", true);
    if (logoSprite !is null)
        logoSprite.visible = enable;
}

void CreateLogo()
{
    // Get logo texture
    Texture2D@ logoTexture = cache.GetResource("Texture2D", "Textures/LogoLarge.png");
    if (logoTexture is null)
        return;
    Sprite@ logoSprite = ui.root.CreateChild("Sprite", "logo");
    logoSprite.texture = logoTexture;
    int textureWidth = logoTexture.width;
    int textureHeight = logoTexture.height;
    logoSprite.SetScale(256.0f / textureWidth);
    logoSprite.SetSize(textureWidth, textureHeight);
    logoSprite.SetHotSpot(0, textureHeight);
    logoSprite.SetAlignment(HA_LEFT, VA_BOTTOM);
    logoSprite.opacity = 0.75f;
    logoSprite.priority = -100;
}

void CreateUI()
{
    // Create a Cursor UI element because we want to be able to hide and show it at will. When hidden, the mouse cursor will
    // control the camera, and when visible, it will point the raycast target
    //XMLFile@ style = cache.GetResource("XMLFile", "UI/DefaultStyle.xml");
    //Cursor@ cursor = Cursor();
    //cursor.SetStyleAuto(style);
    //ui.cursor = cursor;
    // Set starting position of the cursor at the rendering window center
    //cursor.SetPosition(graphics.width / 2, graphics.height / 2);
    // input.SetMouseVisible(true);
    Text@ text = ui.root.CreateChild("Text", "debug");
    // for preload font
    text.SetFont(cache.GetResource("Font", "Fonts/UbuntuMono-R.ttf"), 12);
    text.horizontalAlignment = HA_LEFT;
    text.verticalAlignment = VA_TOP;
    text.SetPosition(0, 20);
    text.color = Color(0, 0, 1);
    // text.textEffect = TE_SHADOW;
}

void ShootBox(Scene@ _scene)
{
    Node@ cameraNode = gCameraMgr.GetCameraNode();
    Node@ boxNode = _scene.CreateChild("SmallBox");
    boxNode.position = cameraNode.position;
    boxNode.rotation = cameraNode.rotation;
    boxNode.SetScale(1.0);
    StaticModel@ boxObject = boxNode.CreateComponent("StaticModel");
    boxObject.model = cache.GetResource("Model", "Models/Box.mdl");
    boxObject.material = cache.GetResource("Material", "Materials/StoneEnvMapSmall.xml");
    boxObject.castShadows = true;
    RigidBody@ body = boxNode.CreateComponent("RigidBody");
    body.mass = 0.25f;
    body.friction = 0.75f;
    body.collisionLayer = COLLISION_LAYER_PROP;
    CollisionShape@ shape = boxNode.CreateComponent("CollisionShape");
    shape.SetBox(Vector3(1.0f, 1.0f, 1.0f));
    body.linearVelocity = cameraNode.rotation * Vector3(0.0f, 0.25f, 1.0f) * 10.0f;
}

void ShootSphere(Scene@ _scene)
{
    Node@ cameraNode = gCameraMgr.GetCameraNode();
    Node@ sphereNode = _scene.CreateChild("Sphere");
    sphereNode.position = cameraNode.position;
    sphereNode.rotation = cameraNode.rotation;
    sphereNode.SetScale(1.0);
    StaticModel@ boxObject = sphereNode.CreateComponent("StaticModel");
    boxObject.model = cache.GetResource("Model", "Models/Sphere.mdl");
    boxObject.material = cache.GetResource("Material", "Materials/StoneSmall.xml");
    boxObject.castShadows = true;
    RigidBody@ body = sphereNode.CreateComponent("RigidBody");
    body.mass = 1.0f;
    body.rollingFriction = 0.15f;
    body.collisionLayer = COLLISION_LAYER_PROP;
    CollisionShape@ shape = sphereNode.CreateComponent("CollisionShape");
    shape.SetSphere(1.0f);
    body.linearVelocity = cameraNode.rotation * Vector3(0.0f, 0.25f, 1.0f) * 10.0f;
}


void CreateEnemy(Scene@ _scene)
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return;

    EnemyManager@ em = GetEnemyMgr();
    if (em is null)
        return;

    IntVector2 pos = ui.cursorPosition;
    // Check the cursor is visible and there is no UI element in front of the cursor
    if (ui.GetElementAt(pos, true) !is null)
            return;

    Camera@ camera = GetCamera();
    if (camera is null)
        return;

    Ray cameraRay = camera.GetScreenRay(float(pos.x) / graphics.width, float(pos.y) / graphics.height);
    float rayDistance = 100.0f;
    PhysicsRaycastResult result = scene_.physicsWorld.RaycastSingle(cameraRay, rayDistance, COLLISION_LAYER_LANDSCAPE);
    if (result.body is null)
        return;

    if (result.body.node.name != "floor")
        return;

    em.CreateEnemy(result.position, Quaternion(0, Random(360), 0), "Thug");
}

Player@ GetPlayer()
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return null;
    Node@ characterNode = scene_.GetNode(playerId);
    if (characterNode is null)
        return null;
    return cast<Player>(characterNode.scriptObject);
}

Camera@ GetCamera()
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return null;
    Node@ cameraNode = scene_.GetNode(cameraId);
    if (cameraNode is null)
        return null;
    return cameraNode.GetComponent("Camera");
}

EnemyManager@ GetEnemyMgr()
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return null;
    return cast<EnemyManager>(scene_.GetScriptObject("EnemyManager"));
}

void SubscribeToEvents()
{
    SubscribeToEvent("Update", "HandleUpdate");
    SubscribeToEvent("PostRenderUpdate", "HandlePostRenderUpdate");
    SubscribeToEvent("KeyDown", "HandleKeyDown");
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown");
    SubscribeToEvent("AsyncLoadFinished", "HandleSceneLoadFinished");
    SubscribeToEvent("AsyncLoadProgress", "HandleAsyncLoadProgress");
    SubscribeToEvent("CameraEvent", "HandleCameraEvent");
}

void HandleUpdate(StringHash eventType, VariantMap& eventData)
{
    float timeStep = eventData["TimeStep"].GetFloat();

    gInput.Update(timeStep);
    gCameraMgr.Update(timeStep);
    gGame.Update(timeStep);

    ExecuteCommand();

    if (script.defaultScene is null)
        return;

    if (drawDebug > 0)
    {
        String debugText = "camera position=" + gCameraMgr.GetCameraNode().worldPosition.ToString() + "\n";
        debugText += gInput.GetDebugText();

        Player@ player = GetPlayer();
        if (player !is null)
            debugText += player.GetDebugText();

        Text@ text = ui.root.GetChild("debug", true);
        if (text !is null)
            text.text = debugText;
    }

    if (autoCounter)
    {
        EnemyManager@ em = GetEnemyMgr();
        if (em is null)
            return;

        int num = em.GetNumOfEnemyHasFlag(FLAGS_COUNTER);
        // Print("autoCounter flags -- attack num = " + num);
        if (num == 2)
        {
            Print("==========================Auto Counter Start==========================");
            Player@ player = GetPlayer();
            if (player !is null)
                player.Counter();
            Print("==========================Auto Counter End==========================");
        }
    }
}

void HandlePostRenderUpdate(StringHash eventType, VariantMap& eventData)
{
    Scene@ scene_ = script.defaultScene;
    if (scene_ is null)
        return;
    gGame.PostRenderUpdate();

    DebugRenderer@ debug = scene_.debugRenderer;
    if (drawDebug == 0)
        return;

    if (drawDebug > 0)
    {
        gCameraMgr.DebugDraw(debug);
        debug.AddNode(scene_, 1.0f, false);
        Player@ player = GetPlayer();
        if (player !is null)
            player.DebugDraw(debug);
    }
    if (drawDebug > 1)
    {
        EnemyManager@ em = GetEnemyMgr();
        if (em !is null)
            em.DebugDraw(debug);
    }
    if (drawDebug > 2)
        scene_.physicsWorld.DrawDebugGeometry(false);
}

void HandleKeyDown(StringHash eventType, VariantMap& eventData)
{
    Scene@ scene_ = script.defaultScene;
    int key = eventData["Key"].GetInt();
    gGame.OnKeyDown(key);

    if (key == KEY_F1)
    {
        ++drawDebug;
        if (drawDebug > 3)
            drawDebug = 0;

        Text@ text = ui.root.GetChild("debug", true);
        if (text !is null)
            text.visible = drawDebug != 0;
    }
    else if (key == KEY_F2)
        debugHud.ToggleAll();
    else if (key == KEY_F3)
        console.Toggle();
    else if (key == KEY_F4)
    {
        Camera@ cam = GetCamera();
        if (cam !is null)
            cam.fillMode = (cam.fillMode == FILL_SOLID) ? FILL_WIREFRAME : FILL_SOLID;
    }
    else if (key == 'R')
        scene_.updateEnabled = !scene_.updateEnabled;
    else if (key == 'T')
    {
        if (scene_.timeScale >= 0.999f)
            scene_.timeScale = 0.25f;
        else
            scene_.timeScale = 1.0f;
    }
    else if (key == KEY_1)
        ShootSphere(scene_);
    else if (key == KEY_2)
        ShootBox(scene_);
    else if (key == KEY_3)
        CreateEnemy(scene_);
    else if (key == KEY_4)
    {
        CameraController@ cc = gCameraMgr.currentController;
        if (cc.nameHash == StringHash("Debug"))
            gCameraMgr.SetCameraController("ThirdPerson");
        else
            gCameraMgr.SetCameraController("Debug");
    }
    else if (key == KEY_5)
    {
        VariantMap data;
        data[TARGET_FOV] = 60;
        SendEvent("CameraEvent", data);
    }
    else if (key == KEY_6)
    {
        colorGradingIndex ++;
        SetColorGrading(colorGradingIndex);
    }

    if (test_ragdoll)
    {
        if (key == 'E')
        {
            Player@ player = GetPlayer();
            if (player is null)
                return;

            Node@ renderNode = player.GetNode().children[0];
            SendAnimationTriger(renderNode, RAGDOLL_STOP);

            AnimationController@ ctl = renderNode.GetComponent("AnimationController");
            Animation@ anim = Animation();
            String name = "Test_Pose";
            anim.name = name;
            anim.animationName = name;
            FillAnimationWithCurrentPose(anim, renderNode);
            cache.AddManualResource(anim);

            AnimatedModel@ model = renderNode.GetComponent("AnimatedModel");
            AnimationState@ state = model.AddAnimationState(anim);
            state.weight = 1.0f;
            ctl.PlayExclusive(anim.name, LAYER_MOVE, false, 0.0f);

            int ragdoll_direction = player.GetNode().vars[ANIMATION_INDEX].GetInt();
            String name1 = ragdoll_direction == 0 ? "TG_Getup/GetUp_Back" : "TG_Getup/GetUp_Front";
            PlayAnimation(ctl, GetAnimationName(name1), LAYER_MOVE, false, 0.25f, 0.0, 0.0);
        }
        else if (key == 'F')
        {
            Player@ player = GetPlayer();
            if (player is null)
                return;

            Node@ renderNode = player.GetNode().children[0];
            AnimationController@ ctl = renderNode.GetComponent("AnimationController");
            int ragdoll_direction = player.GetNode().vars[ANIMATION_INDEX].GetInt();
            String name1 = ragdoll_direction == 0 ? "TG_Getup/GetUp_Back" : "TG_Getup/GetUp_Front";
            ctl.SetSpeed(GetAnimationName(name1), 1.0);
        }
    }
    else
    {
        if (key == 'E')
        {
            //String testName = "TG_Getup/GetUp_Back";
            //String testName = "TG_BM_Counter/Counter_Leg_Front_01";
            //String testName = "TG_HitReaction/Push_Reaction";
            String testName = "BM_Movement/Evade_Right_01";
            //String testName = "TG_HitReaction/HitReaction_Back_NoTurn";
            //String testName = "BM_Attack/Attack_Far_Back_04";
            Player@ player = GetPlayer();
            if (player !is null)
                player.TestAnimation(testName);
        }
        else if (key == 'F')
        {
            scene_.timeScale = 0.25f;
            // SetWorldTimeScale(scene_, 1);
        }
        else if (key == 'O')
        {
            Node@ n = scene_.GetChild("thug2");
            n.vars[ANIMATION_INDEX] = RandomInt(4);
            Thug@ thug = cast<Thug>(n.scriptObject);
            thug.stateMachine.ChangeState("HitState");
        }
    }
}

void HandleMouseButtonDown(StringHash eventType, VariantMap& eventData)
{
    int button = eventData["Button"].GetInt();
    if (button == MOUSEB_RIGHT)
    {
        IntVector2 pos = ui.cursorPosition;
        // Check the cursor is visible and there is no UI element in front of the cursor
        if (ui.GetElementAt(pos, true) !is null)
            return;

        CreateDrag(float(pos.x), float(pos.y));
        SubscribeToEvent("MouseMove", "HandleMouseMove");
        SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp");
    }
}

void HandleMouseButtonUp(StringHash eventType, VariantMap& eventData)
{
    int button = eventData["Button"].GetInt();
    if (button == MOUSEB_RIGHT)
    {
        DestroyDrag();
        UnsubscribeFromEvent("MouseMove");
        UnsubscribeFromEvent("MouseButtonUp");
    }
}

void HandleMouseMove(StringHash eventType, VariantMap& eventData)
{
    int x = input.mousePosition.x;
    int y = input.mousePosition.y;
    MoveDrag(float(x), float(y));
}


void HandleSceneLoadFinished(StringHash eventType, VariantMap& eventData)
{
    Print("HandleSceneLoadFinished");
    gGame.OnSceneLoadFinished(eventData["Scene"].GetPtr());
}

void HandleAsyncLoadProgress(StringHash eventType, VariantMap& eventData)
{
    Print("HandleAsyncLoadProgress");
    Scene@ _scene = eventData["Scene"].GetPtr();
    float progress = eventData["Progress"].GetFloat();
    int loadedNodes = eventData["LoadedNodes"].GetInt();
    int totalNodes = eventData["TotalNodes"].GetInt();
    int loadedResources = eventData["LoadedResources"].GetInt();
    int totalResources = eventData["TotalResources"].GetInt();
    gGame.OnAsyncLoadProgress(_scene, progress, loadedNodes, totalNodes, loadedResources, totalResources);
}

void HandleCameraEvent(StringHash eventType, VariantMap& eventData)
{
    // Print("HandleCameraEvent");
    gCameraMgr.OnCameraEvent(eventData);
}

int FindRenderCommand(RenderPath@ path, const String&in tag)
{
    for (uint i=0; i<path.numCommands; ++i)
    {
        if (path.commands[i].tag == tag)
            return i;
    }
    return -1;
}

void ChangeRenderCommandTexture(RenderPath@ path, const String&in tag, const String&in texture, TextureUnit unit)
{
    int i = FindRenderCommand(path, tag);
    if (i < 0)
    {
        Print("Can not find renderpath tag " + tag);
        return;
    }

    RenderPathCommand cmd = path.commands[i];
    cmd.textureNames[unit] = texture;
    path.commands[i] = cmd;
}

void SetColorGrading(int index)
{
    Array<String> colorGradingTextures = { "Vintage", "BleachBypass",
    "CrossProcess", "LUT_01", "colorLUT_01", "colorLUT_02", "LUT_Greenish", "LUT_Reddish", "LUT_Sepia",
    "Dream", "Negative", "Rainbow", "Posterize", "Noire", "SciFi", "SinCity"};
    if (index >= colorGradingTextures.length)
        index = 0;
    colorGradingIndex = index;
    ChangeRenderCommandTexture(renderer.viewports[0].renderPath, "ColorCorrection", "textures/LUT/" + colorGradingTextures[index] + ".xml", TU_VOLUMEMAP);
}

void ExecuteCommand()
{
    String command = GetConsoleInput();
    if(command.length == 0)
        return;

    Print("######### Console Input: [" + command + "] #############");

    if (command == "dump")
    {
        String debugText = "camera position=" + gCameraMgr.GetCameraNode().worldPosition.ToString() + "\n";
        debugText += gInput.GetDebugText();

        Scene@ scene_ = script.defaultScene;
        if (scene_ !is null)
        {
            Array<Node@> nodes = scene_.GetChildrenWithScript("GameObject", true);
            for (uint i=0; i<nodes.length; ++i)
            {
                GameObject@ object = cast<GameObject@>(nodes[i].scriptObject);
                if (object !is null)
                    debugText += object.GetDebugText();
            }
        }
        Print(debugText);
    }
    else if (command == "anim")
    {
        String testName = "BM_Attack/Attack_Close_Forward_02";
        Player@ player = GetPlayer();
        if (player !is null)
            player.TestAnimation(testName);
    }
    else if (command == "stop")
    {
        gMotionMgr.Stop();
        Scene@ scene_ = script.defaultScene;
        if (scene_ is null)
            return;
        scene_.Remove();
    }
    else if (command == "attack")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Attack();
    }
    else if (command == "evade")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Evade();
    }
    else if (command == "counter")
    {
        Player@ player = GetPlayer();
        if (player !is null)
            player.Counter();
    }
    else if (command == "avoid")
    {
        EnemyManager@ em = GetEnemyMgr();
        if (em is null)
            return;
        em.CreateEnemy(Vector3(0,0,0), Quaternion(0,0,0), "Thug");
        em.CreateEnemy(Vector3(0,0,0), Quaternion(0,0,0), "Thug");
    }
    else if (command == "autocounter")
    {
        autoCounter = !autoCounter;
        Print("Set autoCounter=" + autoCounter);
    }
}