using UnityEngine;

public static class ObjectResizerExtension
{
    public static void AddOrUpdateCollider(this GameObject go)
    {
        // Calculate bounds from renderers
        var renderers = go.GetComponentsInChildren<Renderer>();
        if (renderers.Length == 0)
        {
            Debug.LogWarning("No renderers found, cannot create collider");
            return;
        }

        Bounds bounds = renderers[0].bounds;
        for (int i = 1; i < renderers.Length; i++)
            bounds.Encapsulate(renderers[i].bounds);

        // Add collider on root
        var box = go.AddComponent<BoxCollider>();

        // Convert world bounds to local space
        box.center = go.transform.InverseTransformPoint(bounds.center);
        box.size = go.transform.InverseTransformVector(bounds.size);
    }
    
    public static void FitToPlaceholder(this GameObject model, GameObject placeholder)
    {
        Bounds modelBounds = CalculateRendererBounds(model);
        Bounds targetBounds = CalculateTargetBounds(placeholder);

        if (modelBounds.size == Vector3.zero || targetBounds.size == Vector3.zero)
        {
            Debug.LogWarning("Invalid bounds for scaling");
            return;
        }

        // Compute uniform scale so the model fits inside the placeholder
        float scaleX = targetBounds.size.x / modelBounds.size.x;
        float scaleY = targetBounds.size.y / modelBounds.size.y;
        float scaleZ = targetBounds.size.z / modelBounds.size.z;

        float scale = Mathf.Min(scaleX, scaleY, scaleZ);

        model.transform.localScale = Vector3.one * scale;
    }
    
    private static Bounds CalculateRendererBounds(GameObject go)
    {
        var renderers = go.GetComponentsInChildren<Renderer>();
        if (renderers.Length == 0)
            return new Bounds(go.transform.position, Vector3.zero);

        Bounds b = renderers[0].bounds;
        for (int i = 1; i < renderers.Length; i++)
            b.Encapsulate(renderers[i].bounds);

        return b;
    }

    private static Bounds CalculateTargetBounds(GameObject placeholder)
    {
        // Prefer collider if present (your case)
        var col = placeholder.GetComponent<Collider>();
        if (col != null)
            return col.bounds;

        // Fallback to renderer
        var r = placeholder.GetComponent<Renderer>();
        if (r != null)
            return r.bounds;

        return new Bounds(placeholder.transform.position, Vector3.zero);
    }
}