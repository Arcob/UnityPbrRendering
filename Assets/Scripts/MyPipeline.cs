using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using Conditional = System.Diagnostics.ConditionalAttribute;

public class MyPipeline : RenderPipeline{ //RenderPipeline是带有基础实现的IRenderPipeline接口
    public override void Render(
        ScriptableRenderContext renderContext, Camera[] cameras
    )
    {
        base.Render(renderContext, cameras);  // 不渲染任何东西只是检测有没有错，有错的话会输出错误信息

        //renderContext.DrawSkybox(cameras[0]);
        //renderContext.Submit();

        //对每个相机做渲染
        foreach (var camera in cameras)
        {
            Render(renderContext, camera);
        }
    }

    CullResults cull;

    //初始化一个命令缓冲
    CommandBuffer cameraBuffer = new CommandBuffer
    {
        name = "Render Camera"
    };

    void Render(ScriptableRenderContext context, Camera camera)
    {
        //获取剔除参数
        ScriptableCullingParameters cullingParameters;
        //使用该方法自动填充剔除参数
        if (!CullResults.GetCullingParameters(camera, out cullingParameters))
        {
            return;
        }
#if UNITY_EDITOR
        //手动将UI添加到scene界面，用于使UI在scene界面显示
        if (camera.cameraType == CameraType.SceneView)
        {
            //这行会在game界面再添加一次UI，导致game界面UI被渲染两次，故外部嵌套条件
            ScriptableRenderContext.EmitWorldGeometryForSceneView(camera);
        }
#endif

        //使用剔除参数进行剔除，获取剔除结果
        CullResults.Cull(ref cullingParameters, context, ref cull); //使用存起来的cull引用减少gc开销
        //CullResults cull = CullResults.Cull(ref cullingParameters, context); 这一行由于每帧要生成一个新的struct，生成了大量新gc

        //设置摄像机参数，包括vp矩阵
        context.SetupCameraProperties(camera);

        //CameraClearFlags由一系列表示各种状态的二进制位组成
        /*CameraClearFlags clearFlags = camera.clearFlags;
        cameraBuffer.ClearRenderTarget(
            (clearFlags & CameraClearFlags.Depth) != 0,//判断某一位是不是1
            (clearFlags & CameraClearFlags.Color) != 0,
            camera.backgroundColor
        );*/

        //设置帧调试器采样
        cameraBuffer.BeginSample("Render Camera");
        cameraBuffer.ClearRenderTarget(true, false, Color.clear);
       

        //绘制设置
        var drawSettings = new DrawRendererSettings(
            camera, new ShaderPassName("SRPDefaultUnlit") //传入Unity默认Unlit shader的名字
        );
        //绘制不透明物体前设置物体的渲染次序，按zbuffer从近到远的次序渲染
        drawSettings.sorting.flags = SortFlags.CommonOpaque;

        //由于透明层不会绘制zbuffer，故若绘制次序在skybox之前一定会被skybox遮挡
        //过滤器设置，默认为空过滤所有东西，true表示不过滤任何东西全部显示
        var filterSettings = new FilterRenderersSettings(true)
        {
            renderQueueRange = RenderQueueRange.opaque//在绘制天空盒之前先设置只渲染opaque层以及之前（0-2500）
        };

        //绘制一次（在天空盒前先绘制opaque层及之前）
        context.DrawRenderers(
            cull.visibleRenderers, ref drawSettings, filterSettings
        );

        //画天空盒
        context.DrawSkybox(camera);

        //绘制透明物体前再次设置物体的渲染次序，因为透明物体需要blend，渲染次序和不透明物体反向，按zbuffer从远到近的次序渲染
        drawSettings.sorting.flags = SortFlags.CommonTransparent;
        //再将filter设置为transparent(2501-5000)用于绘制透明层
        filterSettings.renderQueueRange = RenderQueueRange.transparent;
        //第二次绘制，绘制透明层次
        context.DrawRenderers(
            cull.visibleRenderers, ref drawSettings, filterSettings
        );

        DrawDefaultPipeline(context, camera);

        //帧调试器采样
        cameraBuffer.EndSample("Render Camera");
        //执行命令缓冲区中的命令
        context.ExecuteCommandBuffer(cameraBuffer);
        //释放命令缓冲区
        cameraBuffer.Clear();

        //之前只是把命令缓存了，submit函数执行缓存的命令
        context.Submit();
    }

    Material errorMaterial;

    [Conditional("DEVELOPMENT_BUILD"), Conditional("UNITY_EDITOR")]
    void DrawDefaultPipeline(ScriptableRenderContext context, Camera camera) {
        if (errorMaterial == null)
        {
            Shader errorShader = Shader.Find("Hidden/InternalErrorShader");
            errorMaterial = new Material(errorShader)
            {
                hideFlags = HideFlags.HideAndDontSave
            };
        }

        var drawSettings = new DrawRendererSettings(
            camera, new ShaderPassName("ForwardBase")
        );
        drawSettings.SetShaderPassName(1, new ShaderPassName("PrepassBase"));
        drawSettings.SetShaderPassName(2, new ShaderPassName("Always"));
        drawSettings.SetShaderPassName(3, new ShaderPassName("Vertex"));
        drawSettings.SetShaderPassName(4, new ShaderPassName("VertexLMRGBM"));
        drawSettings.SetShaderPassName(5, new ShaderPassName("VertexLM"));
        drawSettings.SetOverrideMaterial(errorMaterial, 0);

        var filterSettings = new FilterRenderersSettings(true);

        context.DrawRenderers(
            cull.visibleRenderers, ref drawSettings, filterSettings
        );
    }
}
