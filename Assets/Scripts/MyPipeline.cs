using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

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

    void Render(ScriptableRenderContext context, Camera camera)
    {
        //获取剔除参数
        ScriptableCullingParameters cullingParameters;
        //使用该方法自动填充剔除参数
        if (!CullResults.GetCullingParameters(camera, out cullingParameters))
        {
            return;
        }

        //使用剔除参数进行剔除，获取剔除结果
        CullResults cull = CullResults.Cull(ref cullingParameters, context);

        //设置摄像机参数，包括vp矩阵
        context.SetupCameraProperties(camera); 

        //初始化渲染命令缓冲
        var buffer = new CommandBuffer
        {
            name = camera.name // 给命令缓存命名方便debug
        };

        //CameraClearFlags由一系列表示各种状态的二进制位组成
        CameraClearFlags clearFlags = camera.clearFlags;
        buffer.ClearRenderTarget(
            (clearFlags & CameraClearFlags.Depth) != 0,//判断某一位是不是1
            (clearFlags & CameraClearFlags.Color) != 0,
            camera.backgroundColor
        );

        //执行命令缓冲区中的命令
        context.ExecuteCommandBuffer(buffer);
        //释放命令缓冲区
        buffer.Release();

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

        //之前只是把命令缓存了，submit函数执行缓存的命令
        context.Submit();
    }
}
