using DG.Tweening;
using UnityEngine;

[RequireComponent(typeof(Rigidbody), typeof(Collider))]
public class ShotObject : MonoBehaviour
{
    [Header("Launch")]
    [SerializeField] private float launchSpeed = 12f;

    [Header("Pitch While Flying")]
    [SerializeField] private float pitchUpDegPerSecond = 220f;
    [SerializeField] private float maxPitchUp = 90f;

    [Header("Stick Rules")]
    [SerializeField] private LayerMask groundMask;
    [SerializeField] private LayerMask wallMask;
    [SerializeField] private LayerMask towerMask;
    [SerializeField] private float stickOffset = 0.002f; // tiny offset so it doesn't z-fight into the surface

    private Rigidbody _rb;
    private Vector3 _targetScale;
    private bool _inFlight;
    private float _dmgMultiplier;

    private void OnEnable()
    {
        var transform1 = transform;
        _targetScale = transform1.localScale;
        transform1.localScale = Vector3.zero;
        _rb = GetComponent<Rigidbody>();
    }

    public void OnShoot(float dmgMultiplier)
    {
        _dmgMultiplier = dmgMultiplier;
        transform.DOScale(_targetScale, 1f);
        
        // Reset physics state
        _rb.isKinematic = false;
        _rb.useGravity = true;
        _rb.linearVelocity = Vector3.zero;
        _rb.angularVelocity = Vector3.zero;

        _inFlight = true;

        // Launch along current forward (your prefab pitch like -28° gives it an arc)
        _rb.AddForce(transform.forward * launchSpeed, ForceMode.Impulse);
    }

    private void FixedUpdate()
    {
        if (!_inFlight) return;

        // Rotate the object’s X upwards over time (visual “cannonball” pitch)
        var e = transform.eulerAngles;
        var x = NormalizeAngle(e.x);
        var next = Mathf.MoveTowards(x, maxPitchUp, pitchUpDegPerSecond * Time.fixedDeltaTime);
        transform.rotation = Quaternion.Euler(next, e.y, e.z);
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (!_inFlight) return;

        var otherLayer = collision.gameObject.layer;
        
        if (IsInMask(otherLayer, groundMask))
        {
            StickToGround(collision);
            return;
        }

        if (IsInMask(otherLayer, wallMask))
        {
            StickToWall(collision);
            return;
        }

        if (IsInMask(otherLayer, towerMask))
        {
            var towerObject = collision.gameObject.GetComponent<Tower>();
            if (towerObject)
            {
                towerObject.OnTowerShot(_dmgMultiplier);
                Destroy(gameObject);
                return;
            }
        }
    }

    private void StickToGround(Collision c)
    {
        _inFlight = false;

        _rb.linearVelocity = Vector3.zero;
        _rb.angularVelocity = Vector3.zero;
        _rb.useGravity = false;
        _rb.isKinematic = true;

        var e = transform.eulerAngles;
        var t = transform;
        t.rotation = Quaternion.Euler(90f, e.y, e.z);

        var cp = c.GetContact(0);

        var groundCol = c.collider;
        var myCol = GetComponent<Collider>();
        if (myCol == null)
        {
            t.position = cp.point + cp.normal * stickOffset;
            return;
        }

        var position = t.position;
        var onGround = groundCol.ClosestPoint(position);
        var mySupportTowardGround = myCol.ClosestPoint(onGround - cp.normal * 10f);

        var push = Vector3.Dot(onGround - mySupportTowardGround, cp.normal);
        position = position + cp.normal * push + cp.normal * stickOffset;
        t.position = position;
    }

    private void StickToWall(Collision c)
    {
        _inFlight = false;

        _rb.linearVelocity = Vector3.zero;
        _rb.angularVelocity = Vector3.zero;
        _rb.useGravity = false;
        _rb.isKinematic = true;

        var cp = c.GetContact(0);

        var wallForward = Vector3.ProjectOnPlane(-cp.normal, Vector3.up);
        if (wallForward.sqrMagnitude < 0.0001f)
            wallForward = transform.forward;

        var t = transform;
        t.rotation = Quaternion.LookRotation(wallForward.normalized, Vector3.up);

        var wallCol = c.collider;
        var myCol = GetComponent<Collider>();
        if (myCol == null)
        {
            t.position = cp.point + cp.normal * stickOffset;
            return;
        }

        var position = t.position;
        var onWall = wallCol.ClosestPoint(position);
        
        var mySupportTowardWall = myCol.ClosestPoint(onWall - cp.normal * 10f);
        var push = Vector3.Dot(onWall - mySupportTowardWall, cp.normal);
        position = position + cp.normal * push + cp.normal * stickOffset;
        t.position = position;
    }

    private static bool IsInMask(int layer, LayerMask mask)
        => (mask.value & (1 << layer)) != 0;

    private static float NormalizeAngle(float a)
    {
        a %= 360f;
        if (a > 180f) a -= 360f;
        return a;
    }
}