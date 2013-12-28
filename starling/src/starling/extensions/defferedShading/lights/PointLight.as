package starling.extensions.defferedShading.lights
{
	import com.adobe.utils.AGALMiniAssembler;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.VertexBuffer3D;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	
	import starling.core.RenderSupport;
	import starling.core.Starling;
	import starling.display.DisplayObject;
	import starling.errors.MissingContextError;
	import starling.events.Event;
	import starling.extensions.defferedShading.MaterialProperties;
	import starling.extensions.defferedShading.RenderPass;
	import starling.extensions.defferedShading.Utils;
	import starling.extensions.defferedShading.renderer_internal;
	import starling.utils.VertexData;
	
	use namespace renderer_internal;

	/**
	 * Represents a 360 degree light.
	 */
	public class PointLight extends Light
	{		
		private static var PROGRAM_NAME:String = 'PointLight';
		
		private var mNumEdges:int = 6;
		private var realRadius:Number;

		// Geometry data
		
		private var vertexData:VertexData;
		private var vertexBuffer:VertexBuffer3D;
		private var indexData:Vector.<uint>;
		private var indexBuffer:IndexBuffer3D;
		
		// Helper objects
		
		private static var sHelperMatrix:Matrix = new Matrix();
		private static var position:Point = new Point();
		private static var sRenderAlpha:Vector.<Number> = new <Number>[1.0, 1.0, 1.0, 1.0];
		
		// Constants
		
		private static var constants:Vector.<Number> = new <Number>[0.5, 1.0, 2.0, 0.0];
		private static var lightProps:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
		private static var lightColor:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
		private static var halfVec:Vector.<Number> = new <Number>[0.0, 0.0, 1.0, 0.0];
		private static var lightPosition:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
		private static var attenuationConstants:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
		private static var specularParams:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
		
		public function PointLight(color:uint = 0xFFFFFF, strength:Number = 1.0, radius:Number = 50, attenuation:Number = 15)
		{
			super(color, strength);
			
			this.radius = radius;
			this.attenuation = 15;
			this.strength = strength;
			
			// Handle lost context			
			Starling.current.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
		}
		
		public override function dispose():void
		{
			Starling.current.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
			
			if (vertexBuffer) vertexBuffer.dispose();
			if (indexBuffer)  indexBuffer.dispose();
			
			super.dispose();
		}
		
		public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle=null):Rectangle
		{
			if (resultRect == null) resultRect = new Rectangle();
			
			var transformationMatrix:Matrix = targetSpace == this ? 
				null : getTransformationMatrix(targetSpace, sHelperMatrix);
			
			return vertexData.getBounds(transformationMatrix, 0, -1, resultRect);
		}
		
		public override function render(support:RenderSupport, alpha:Number):void
		{
			if(support.renderPass == RenderPass.DEFERRED_LIGHTS)
			{
				// always call this method when you write custom rendering code!
				// it causes all previously batched quads/images to render.
				support.finishQuadBatch();
				
				// make this call to keep the statistics display in sync.
				support.raiseDrawCount();
				
				sRenderAlpha[0] = sRenderAlpha[1] = sRenderAlpha[2] = 1.0;
				sRenderAlpha[3] = alpha * this.alpha;
				
				var context:Context3D = Starling.context;
				if (context == null) throw new MissingContextError();
				
				// Don`t apply regular blend mode
				// support.applyBlendMode(false);
				
				// Set constants
				
				position.setTo(0, 0);
				localToGlobal(position, position);
				lightPosition[0] = position.x;
				lightPosition[1] = position.y;
				lightPosition[2] = stage.stageWidth;
				lightPosition[3] = stage.stageHeight;
					
				lightProps[0] = _radius;
				lightProps[1] = _strength;
				lightProps[3] = _radius * _radius;
				
				lightColor[0] = _colorR;
				lightColor[1] = _colorG;
				lightColor[2] = _colorB;
				
				attenuationConstants[0] = _attenuation;
				attenuationConstants[1] = 1 / (attenuationConstants[0] + 1);
				attenuationConstants[2] = 1 - attenuationConstants[1];
				
				specularParams[0] = MaterialProperties.SPECULAR_POWER_SCALE;
				specularParams[1] = MaterialProperties.SPECULAR_INTENSITY_SCALE;
				
				// activate program (shader) and set the required buffers / constants 
				context.setProgram(Starling.current.getProgram(PROGRAM_NAME));
				context.setVertexBufferAt(0, vertexBuffer, VertexData.POSITION_OFFSET, Context3DVertexBufferFormat.FLOAT_2); 
				context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 0, support.mvpMatrix3D, true);            
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, constants, 1);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, lightPosition, 1);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 2, lightProps, 1);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 3, lightColor, 1);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 4, halfVec, 1);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 5, attenuationConstants, 1);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 6, specularParams, 1);
				
				// finally: draw the object!
				context.drawTriangles(indexBuffer, 0, mNumEdges);
				
				// reset buffers
				context.setVertexBufferAt(0, null);
				context.setVertexBufferAt(1, null);
			}			
		}
		
		/*-----------------------------
		Event handlers
		-----------------------------*/
		
		private function onContextCreated(event:Event):void
		{
			// The old context was lost, so we create new buffers and shaders			
			createBuffers();
			registerPrograms();
		}
		
		/*-----------------------------
		Helpers
		-----------------------------*/
		
		private static function registerPrograms():void
		{
			var target:Starling = Starling.current;
			
			if(target.hasProgram(PROGRAM_NAME))
				return; // already registered
			
			// va0 - position
			// vc0 - mvpMatrix (occupies 4 vectors, vc0 - vc3)			
			
			var vertexProgramCode:String = 
				Utils.joinProgramArray(
					[
						'm44 vt0, va0, vc0',
						'mov op, vt0',
						'mov v0, vt0'
					]
				);		
			
			// fc0 - constants [0.5, 1, 2, 0]
			// fc1 - light position in eye coordinates, screen width/height [x, y, screenWidth, screenHeight]
			// fc2 - light properties [radius, strength, 0, radius^2]
			// fc3 - light color [r, g, b, 0]
			// fc4 - halfVec [0, 0, 1, 0]
			// fc5 - attenuation constants [0, 0, 0, att_s]
			// fc6 - specular param scale values [specularPowerScale, specularIntensityScale, 0, 0]
			
			var fragmentProgramCode:String =
				Utils.joinProgramArray(
					[
						// Unpack screen coords to [0, 1] by
						// multiplying by 0.5 and then adding 0.5						
						
						'mul ft0.xyxy, v0.xyxy, fc0.xxxx',
						'add ft0.xy, ft0.xy, fc0.xx',
						'sub ft0.y, fc0.y, ft0.y',
						
						// Sample normals to ft1
						
						'tex ft1, ft0.xy, fs0 <2d, clamp, linear, mipnone>',
						
						// Then unpack normals from [0, 1] to [-1, 1]
						// by multiplying by 2 and then subtracting 1
						
						'mul ft1.xyz, ft1.xyz, fc0.zzz',
						'sub ft1.xyz, ft1.xyz, fc0.yyy',
						
						// Sample depth to ft2 
						
						'tex ft2, ft0.xy, fs1 <2d, clamp, linear, mipnone>',
						
						// Put specular power and specular intensity to ft0.zw
						// Those are stored in yz of depth
						// Also, unscale both appropriately to get original value
						
						'mul ft0.z, ft2.y, fc6.x',
						'mul ft0.w, ft2.z, fc6.y',
						
						// Calculate pixel position in eye space
						
						'mul ft3.xyxy, ft0.xyxy, fc1.zwzw',
						
						// float3 lightDirection = lightPosition - pixelPosition;
						'sub ft3.xy, fc1.xy, ft3.xy',
						'mov ft3.zw, fc0.ww',
						
						// Save length(lightDirection) to ft7.x for later
						'pow ft7.x, ft3.x, fc0.z',
						'pow ft7.y, ft3.y, fc0.z',
						'add ft7.x, ft7.x, ft7.y',
						'sqt ft7.x, ft7.x',
						
						// float3 lightDirNorm = normalize(lightDirection);
						'nrm ft4.xyz, ft3.xyz',
						
						// float amount = max(dot(normal, lightDirNorm), 0);
						// Put it in ft5.x
						'dp3 ft5.x, ft1.xyz, ft4.xyz',
						'max ft5.x, ft5.x, fc0.w',
						
						// Linear attenuation
						// http://blog.slindev.com/2011/01/10/natural-light-attenuation/
						// Put it in ft5.y					
						'dp3 ft5.y, ft3.xyz, ft3.xyz',
						'div ft5.y, ft5.y, fc2.w',
						'mul ft5.y, ft5.y, fc5.x',
						'add ft5.y, ft5.y, fc0.y',
						'rcp ft5.y, ft5.y',						
						'sub ft5.y, ft5.y, fc5.y',
						'div ft5.y, ft5.y, fc5.z',
						
						// float3 reflect = normalize(2 * amount * normal - lightDirNorm);
						// Won`t need saved normal anymore, save to ft1
						'mul ft1.xyz, ft1.xyz, fc0.z',
						'mul ft1.xyz, ft1.xyz, ft5.x',
						'sub ft1.xyz, ft1.xyz, ft4.xyz',
						'nrm ft1.xyz, ft1.xyz',
						
						// float specular = min(pow(saturate(dot(reflect, halfVec)), specularPower), amount);
						// Put it in ft5.z
						'dp3 ft5.z, ft1.xyz, fc4.xyz',
						'sat ft5.z, ft5.z',
						'pow ft5.z, ft5.z, ft0.z',
						'min ft5.z, ft5.z, ft5.x',
						
						// Output.Color = lightColor * coneAttenuation * lightStrength
						'mul ft6.xyz, ft5.yyy, fc3.xyz',
						'mul ft6.xyz, ft6.xyz, fc2.y',
						
						// + (coneAttenuation * specular * specularStrength)
						// And don`t apply specular here - move it to alpha channel of the output
						// Also, multiply specular by light strength
						
						'mul ft7.x, ft5.y, ft5.z',
						'mul ft7.x, ft7.x, ft0.w',
						'mov ft6.w, ft7.x',
						'mul ft6.w, ft6.w, fc2.y',
						'mov oc, ft6'
					]
				);
			
			var vertexProgramAssembler:AGALMiniAssembler = new AGALMiniAssembler();
			vertexProgramAssembler.assemble(Context3DProgramType.VERTEX, vertexProgramCode);
			
			var fragmentProgramAssembler:AGALMiniAssembler = new AGALMiniAssembler();
			fragmentProgramAssembler.assemble(Context3DProgramType.FRAGMENT, fragmentProgramCode);
			
			target.registerProgram(PROGRAM_NAME, vertexProgramAssembler.agalcode,
				fragmentProgramAssembler.agalcode);
		}
		
		private function calculateRealRadius(radius:Number):void
		{			
			realRadius = 2 * radius / Math.sqrt(3);
		}
		
		private function setupVertices():void
		{
			var i:int;
			
			// Create vertices			
			vertexData = new VertexData(mNumEdges+1);
			
			for(i = 0; i < mNumEdges; ++i)
			{
				var edge:Point = Point.polar(realRadius, i * 2 * Math.PI / mNumEdges);
				vertexData.setPosition(i, edge.x, edge.y);
			}
			
			// Center vertex
			vertexData.setPosition(mNumEdges, 0.0, 0.0);
			
			// Create indices that span up the triangles			
			indexData = new <uint>[];
			
			for(i = 0; i < mNumEdges; ++i)
			{
				indexData.push(mNumEdges, i, (i + 1) % mNumEdges);
			}			
		}
		
		private function createBuffers():void
		{
			var context:Context3D = Starling.context;
			if (context == null) throw new MissingContextError();
			
			if (vertexBuffer) vertexBuffer.dispose();
			if (indexBuffer)  indexBuffer.dispose();
	 		
			vertexBuffer = context.createVertexBuffer(vertexData.numVertices, VertexData.ELEMENTS_PER_VERTEX);
			vertexBuffer.uploadFromVector(vertexData.rawData, 0, vertexData.numVertices);
			
			indexBuffer = context.createIndexBuffer(indexData.length);
			indexBuffer.uploadFromVector(indexData, 0, indexData.length);
		}
		
		/*-----------------------------
		Properties
		-----------------------------*/
		
		private var _attenuation:Number;
		
		/**
		 * Attenuation coefficient. Lesser values mean more spread light.
		 * If value is negative or equal to zero, it will be set to Number.MIN_VALUE.
		 */
		public function get attenuation():Number
		{ 
			return _attenuation;
		}
		public function set attenuation(value:Number):void
		{
			_attenuation = value <= 0 ? Number.MIN_VALUE : value;
		}
		
		private var _radius:Number;
		
		/**
		 * Light radius in pixels.
		 */
		public function get radius():Number
		{ 
			return _radius;
		}
		public function set radius(value:Number):void
		{
			_radius = value;
			calculateRealRadius(value);
			
			// Setup vertex data and prepare shaders			
			setupVertices();
			createBuffers();
			registerPrograms();
		}
		
		private var _castsShadows:Boolean = false;
		
		/**
		 * This light will cast shadows if set to true.
		 */
		public function get castsShadows():Boolean
		{ 
			return _castsShadows;
		}
		public function set castsShadows(value:Boolean):void
		{
			_castsShadows = value;
		}		
	}
}