package starling.extensions.defferedShading
{
	import starling.textures.Texture;

	public class DeferredShadingProperties
	{
		public static const SPECULAR_POWER_SCALE:Number = 256.0;
		public static const SPECULAR_INTENSITY_SCALE:Number = 50.0;
		
		public var normalMap:Texture;
		public var depthMap:Texture;
		public var specularIntensity:Number = 1.0;
		public var specularPower:Number = 10.0;
		
		public function DeferredShadingProperties(normalMap:Texture = null, depthMap:Texture = null)
		{
			this.normalMap = normalMap;
			this.depthMap = depthMap;
		}
	}
}