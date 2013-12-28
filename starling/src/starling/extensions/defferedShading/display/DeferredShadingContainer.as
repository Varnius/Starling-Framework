package starling.extensions.defferedShading.display
{
	import com.adobe.utils.AGALMiniAssembler;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.Program3D;
	import flash.display3D.VertexBuffer3D;
	import flash.geom.Rectangle;
	
	import starling.core.RenderSupport;
	import starling.core.Starling;
	import starling.display.DisplayObject;
	import starling.display.Sprite;
	import starling.events.Event;
	import starling.extensions.defferedShading.RenderPass;
	import starling.extensions.defferedShading.Utils;
	import starling.extensions.defferedShading.renderer_internal;
	import starling.extensions.defferedShading.lights.AmbientLight;
	import starling.extensions.defferedShading.lights.Light;
	import starling.textures.Texture;

	use namespace renderer_internal;
	
	/**
	 * DeferredRenderer. Serves as a container for all other display objects
	 * that should have lighting applied to them.
	 */
	public class DeferredShadingContainer extends Sprite
	{		
		protected var assembler:AGALMiniAssembler = new AGALMiniAssembler();
		
		// Quad
		
		protected var overlayVertexBuffer:VertexBuffer3D;
		protected var overlayIndexBuffer:IndexBuffer3D;
		protected var vertices:Vector.<Number> = new <Number>[-1, 1, 0, 0, 0, -1, -1, 0, 0, 1, 1,  1, 0, 1, 0, 1, -1, 0, 1, 1];
		protected var indices:Vector.<uint> = new <uint>[0,1,2,2,1,3];
		protected var fragmentConstants:Vector.<Number> = new <Number>[1.0, 0.0, 0.0, 0.0];
		
		// Compiled programs
		
		private var combinedResultProgram:Program3D;
		
		// Render targets	
		
		private var renderTargets:Vector.<Texture>;
		public var diffuseRenderTarget:Texture;
		public var normalRenderTarget:Texture;
		public var depthRenderTarget:Texture;
		public var lightPassRenderTarget:Texture;
		
		// Lights
		
		private var lightPassRenderTargets:Vector.<Texture> = new Vector.<Texture>();
		private var lights:Vector.<Light> = new Vector.<Light>();
		private var stageBounds:Rectangle = new Rectangle();
		private var lightBounds:Rectangle = new Rectangle();
		private var ambientConstants:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
		
		// Occluders
		
		private var occluders:Vector.<DisplayObject> = new Vector.<DisplayObject>();
		
		// Misc		
		
		private var prepared:Boolean = false;
		private var prevRenderTargets:Vector.<Texture> = new Vector.<Texture>();
		
		/**
		 * Class constructor. Creates a new instance of DeferredShadingContainer.
		 */
		public function DeferredShadingContainer()
		{
			prepare();
			
			// Handle lost context			
			Starling.current.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
		}
		
		/*---------------------------
		Public methods
		---------------------------*/
		
		/**
		 * Adds light. Only lights added to the container this way will be rendered.
		 */
		public function addLight(light:Light):void
		{
			lights.push(light);
		}
		
		/**
		 * Removes light, so it won`t be rendered.
		 */
		public function removeLight(light:Light):void
		{
			lights.splice(lights.indexOf(light), 1);
		}
		
		/**
		 * Adds occluder. Only occluders added this way will cast shadows.
		 */
		public function addOccluder(occluder:DisplayObject):void
		{
			occluders.push(occluder);
		}
		
		/**
		 * Removes occluder, so it won`t cast shadows anymore.
		 */
		public function removeOccluder(occluder:DisplayObject):void
		{
			occluders.splice(occluders.indexOf(occluder), 1);
		}
		
		public override function dispose():void
		{
			Starling.current.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
			
			for each(var rt:Texture in renderTargets)
			{
				rt.dispose();
			}
			
			overlayVertexBuffer.dispose();
			overlayIndexBuffer.dispose();
			
			super.dispose();
		}
		
		/*---------------------------
		Overrides
		---------------------------*/
		
		private function prepare():void
		{
			var context:Context3D = Starling.context;
			var w:Number = Starling.current.nativeStage.stageWidth;
			var h:Number = Starling.current.nativeStage.stageHeight;			
			
			// Create a quad for rendering full screen passes
			
			overlayVertexBuffer = context.createVertexBuffer(4, 5);
			overlayVertexBuffer.uploadFromVector(vertices, 0, 4);
			overlayIndexBuffer = context.createIndexBuffer(6);
			overlayIndexBuffer.uploadFromVector(indices, 0, 6);			
		
			// Create render targets 
			// FLOAT or HALF_FLOAT textures could be used to increase the precision of specular params
			// No difference for normals or depth because those aren`t calculated at the run time
			
			diffuseRenderTarget = Texture.empty(w, h, false, false, true, -1, Context3DTextureFormat.BGRA);
			normalRenderTarget = Texture.empty(w, h, false, false, true, -1, Context3DTextureFormat.BGRA);
			depthRenderTarget = Texture.empty(w, h, false, false, true, -1, Context3DTextureFormat.BGRA);
			lightPassRenderTarget = Texture.empty(w, h, false, false, true, -1, Context3DTextureFormat.BGRA);
			
			renderTargets = new Vector.<Texture>();
			renderTargets.push(diffuseRenderTarget, normalRenderTarget, depthRenderTarget);
			
			// Create programs
			
			combinedResultProgram = assembler.assemble2(context, 2, VERTEX_SHADER, FRAGMENT_SHADER);			
			prepared = true;
		}
		
		override public function render(support:RenderSupport, parentAlpha:Number):void
		{
			renderExtended(support, parentAlpha);
		}
		
		/*-----------------------------
		Event handlers
		-----------------------------*/
		
		private function onContextCreated(event:Event):void
		{
			prepared = false;
			prepare();
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		private function renderExtended(support:RenderSupport, parentAlpha:Number):void
		{			
			if(!prepared)
			{
				prepare();
			}			
			
			/*----------------------------------
			MRT pass
			----------------------------------*/
			
			var context:Context3D = Starling.context;
			
			prevRenderTargets.length = 0;
			prevRenderTargets.push(support.renderTarget, null, null);

			// Set render targets, clear them and render background only
			
			support.renderTargets = renderTargets;
			
			var prevPass:String = support.renderPass;
			support.renderPass = RenderPass.DEFERRED_MRT;
			
			support.clear();
			super.render(support, parentAlpha);
			support.finishQuadBatch();
			
			/*----------------------------------
			Light pass
			----------------------------------*/
			
			if(lights.length)
			{				
				lightPassRenderTargets.length = 0;
				lightPassRenderTargets.push(lightPassRenderTarget, null, null);
				
				support.renderTargets = lightPassRenderTargets;
				support.renderPass = RenderPass.DEFERRED_LIGHTS;
				
				// Set previously rendered maps
				
				context.setTextureAt(0, normalRenderTarget.base);
				context.setTextureAt(1, depthRenderTarget.base);
				
				// Clear RT
				
				support.clear(0x000000, 0.0);
				context.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ONE);   
				
				var ambientLight:AmbientLight;
				
				for each(var l:Light in lights)
				{
					// If there are multiple ambient lights - use the last one added
					
					if(l is AmbientLight)
					{
						ambientLight = l as AmbientLight;
						continue;
					}
					
					l.getBounds(stage, lightBounds);				
					stageBounds.setTo(0, 0, stage.stageWidth, stage.stageHeight);
					
					var isVisible:Boolean = stageBounds.containsRect(lightBounds) || stageBounds.intersects(lightBounds);
					
					// Render only visible lights
					
					if(isVisible)
					{
						support.pushMatrix();
						
						var obj:DisplayObject = l;
						
						while(obj != stage)
						{
							support.prependMatrix(obj.transformationMatrix);
							obj = obj.parent;
						}						
						
						l.render(support, parentAlpha);
						support.popMatrix();
					}
				}
				
				// Don`t need to set it to null here
				//context.setTextureAt(0, null);
				context.setTextureAt(1, null);
			}		
			
			/*----------------------------------
			Render final shading
			----------------------------------*/
			
			// Set previous pass	
			
			support.renderPass = prevPass;			
			support.renderTargets = prevRenderTargets;

			// Prepare to render combined result
			
			context.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			context.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);                      
			context.setTextureAt(0, diffuseRenderTarget.base);
			context.setTextureAt(1, lightPassRenderTarget.base);
			context.setTextureAt(2, depthRenderTarget.base);
			context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, fragmentConstants);
			
			if(ambientLight)
			{
				ambientConstants[0] = ambientLight._colorR * ambientLight.strength;
				ambientConstants[1] = ambientLight._colorG * ambientLight.strength;
				ambientConstants[2] = ambientLight._colorB * ambientLight.strength;
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, ambientConstants);
			}
			
			context.setProgram(combinedResultProgram);			
			context.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO); 
			support.clear(0x000000, 1.0);
			
			context.drawTriangles(overlayIndexBuffer);
			
			// Clean up
			
			context.setVertexBufferAt(0, null);
			context.setVertexBufferAt(1, null);
			context.setTextureAt(0, null);
			context.setTextureAt(1, null);
			context.setTextureAt(2, null);
			
			support.raiseDrawCount();
		}
		
		/*---------------------------
		Properties
		---------------------------*/
		
		// ..
		
		/*---------------------------
		Programs
		---------------------------*/		

		protected const VERTEX_SHADER:String = 			
			Utils.joinProgramArray(
				[
					'mov op, va0',
					'mov v0, va1'
				]
			);
		
		protected const FRAGMENT_SHADER:String =
			Utils.joinProgramArray(
				[
					// Sample diffuse, lightmap and depth
					'tex ft0, v0, fs0 <2d, clamp, linear, mipnone>',
					'tex ft1, v0, fs1 <2d, clamp, linear, mipnone>',
					'tex ft3, v0, fs2 <2d, clamp, linear, mipnone>',
					
					// Add ambient light
					'add ft1.xyz, ft1.xyz, fc1.xyz',
					
					// Multiply diffuse map by lightmap
					'mul ft2.xyz, ft0.xyz, ft1.xyz',
					
					// Add specular
					'add ft2.xyz, ft2.xyz, ft1.www',				
					
					// Multiply by depth value
					'mul ft2.xyz, ft2.xyz, ft3.xxx',
					
					// Set alpha as 1
					'mov ft2.w, fc0.x',
					'mov oc, ft2'
				]
			);
	}
}