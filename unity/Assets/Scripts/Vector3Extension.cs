using UnityEngine;
using Numerics = System.Numerics;

public static class Vector3Extensions
{
    public static Numerics.Vector3 ToNumerics(this Vector3 v) => new Numerics.Vector3(v.x, v.y, v.z);

    public static Vector3 ToUnity(this Numerics.Vector3 v) => new Vector3(v.X, v.Y, v.Z);
}

public static class QuaternionExtensions
{
    // Unity → System.Numerics
    public static Numerics.Quaternion ToNumerics(this Quaternion q)
        => new Numerics.Quaternion(q.x, q.y, q.z, q.w);

    // System.Numerics → Unity
    public static Quaternion ToUnity(this Numerics.Quaternion q)
        => new Quaternion(q.X, q.Y, q.Z, q.W);
}