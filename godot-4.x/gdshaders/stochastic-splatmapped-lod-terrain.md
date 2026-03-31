# Stochastic Tiling Splat-mapped Terrain with LOD

#### There are a few problems this shader aims to fix:

- Creating tiling textures is annoying and difficult to get right.
- High-detail textures viewed a large distances turn into a mushy mess.
- Getting all of the above to all work together with decent performance (minimal texture samples).

This shader is an all-in-one terrain shader that implements the following:

- A stochastic hexagonal texture tiler.
- A camera UV distance scaler.
- A basic splat-map terrain solution.

## Examples

![Terrain 1 Example](img/terrain-1.png)
![Terrain 2 Example](img/terrain-2.png)

### [Link to Shader](https://github.com/wmboeckman/godot-toolbox/blob/main/godot-4.x/gdshaders/stochastic-splatmapped-lod-terrain.gdshader)

## Credits

This script is a combination of other's work with minimal tweaks made for performance and cohesion.

- [name 1](link1) : shader 1
- [Qtan1](https://godotshaders.com/shader/camera-distance-uv-scaling/) : Camera Distance UV Scaling
- [name 3](link3) : shader 3 