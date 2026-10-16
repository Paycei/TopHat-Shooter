#version 330

// Post-processing: the game passes the finished frame as texture0, plus the
// `time` (seconds) and `resolution` (pixels) uniforms. `strength` is ours,
// set from main.lua with shader:set.

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform float time;
uniform vec2 resolution;
uniform float strength;

out vec4 finalColor;

void main() {
    // A gently curved screen.
    vec2 c = fragTexCoord - 0.5;
    vec2 uv = fragTexCoord + c * dot(c, c) * 0.18 * strength;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Colour fringes: red and blue sampled a hair apart.
    float fringe = 0.0016 * strength;
    vec3 col = vec3(texture(texture0, uv + vec2(fringe, 0.0)).r,
                    texture(texture0, uv).g,
                    texture(texture0, uv - vec2(fringe, 0.0)).b);

    // Scanlines, a dark corner vignette and a faint flicker.
    float scan = 0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159);
    col *= mix(1.0, 0.72 + 0.28 * scan, strength);
    col *= 1.0 - dot(c, c) * 1.1 * strength;
    col *= 1.0 + 0.015 * strength * sin(time * 50.0);

    finalColor = vec4(col, 1.0) * fragColor;
}
