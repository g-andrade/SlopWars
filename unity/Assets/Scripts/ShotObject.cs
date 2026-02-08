using DG.Tweening;
using UnityEngine;

public class ShotObject : MonoBehaviour
{
    [Header("Launch")]
    [SerializeField] private float launchSpeed = 30f;

    [Header("Pitch While Flying")]
    [SerializeField] private float pitchUpDegPerSecond = 220f;
    [SerializeField] private float maxPitchUp = 90f;

    [SerializeField] private float stickOffset = 0.002f; // tiny offset so it doesn't z-fight into the surface

    private Rigidbody _rb;
    private Collider _coll;
    private Vector3 _targetScale;
    private bool _inFlight;
    private float _dmgMultiplier;

    private void OnEnable()
    {
        _rb = GetComponent<Rigidbody>();
        if (!_rb)
            _rb = gameObject.AddComponent<Rigidbody>();

        _coll = GetComponent<Collider>();
        
        var transform1 = transform;
        _targetScale = transform1.localScale;
        transform1.localScale = Vector3.zero;
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
        
        if (otherLayer == LayerMask.NameToLayer("Ground"))
        {
            StickToGround(collision);
            transform.GetChild(0).GetComponent<MeshRenderer>().enabled = false;

            var shield = transform.GetChild(1);
            gameObject.layer = shield.gameObject.layer;
            shield.localScale = Vector3.one * 4f;
            
            shield.gameObject.SetActive(true);
            return;
        }

        if (otherLayer == LayerMask.NameToLayer("Wall"))
        {
            StickToWall(collision);
            return;
        }

        if (otherLayer == LayerMask.NameToLayer("Tower"))
        {
            var towerName = collision.transform.name;
            var towerObject = GameObject.Find($"{towerName}Reference").GetComponent<Tower>();
            if (towerObject)
            {
                towerObject.OnTowerShot(_dmgMultiplier);
                Destroy(gameObject);
                return;
            }
        }

        if ((gameObject.layer == LayerMask.NameToLayer("ProjectilePlayer") && otherLayer == LayerMask.NameToLayer("ShieldOpponent"))
            || (gameObject.layer == LayerMask.NameToLayer("ProjectileOpponent") && otherLayer == LayerMask.NameToLayer("ShieldPlayer")))
        {
            var shieldObject = collision.gameObject;
            if (shieldObject)
            {
                Destroy(shieldObject);
                Destroy(gameObject);
                return;
            }
        }

        if ((gameObject.layer == LayerMask.NameToLayer("ProjectilePlayer") && otherLayer == LayerMask.NameToLayer("ShieldPlayer"))
            || (gameObject.layer == LayerMask.NameToLayer("ProjectileOpponent") && otherLayer == LayerMask.NameToLayer("ShieldOpponent")))
        {
            StickToMiddleObject(collision);
            transform.GetChild(0).GetComponent<MeshRenderer>().enabled = false;

            var shield = transform.GetChild(1);
            gameObject.layer = shield.gameObject.layer;
            shield.localScale = Vector3.one * 3f;
            
            shield.gameObject.SetActive(true);
            return;
        }
    }
    
    private void StickToMiddleObject(Collision c)
    {
        _inFlight = false;

        _rb.linearVelocity = Vector3.zero;
        _rb.angularVelocity = Vector3.zero;
        _rb.useGravity = false;
        _rb.isKinematic = true;

        var t = transform;
        var cp = c.GetContact(0);

        // Align to surface: make our UP point along the surface normal
        // (if your tile's face normal is transform.forward instead, swap Vector3.up -> Vector3.forward)
        t.rotation = Quaternion.FromToRotation(t.up, cp.normal) * t.rotation;

        var targetCol = c.collider;
        if (_coll == null)
        {
            t.position = cp.point + cp.normal * stickOffset;
            return;
        }

        var position = t.position;
        var onTarget = targetCol.ClosestPoint(position);
        var mySupportTowardTarget = _coll.ClosestPoint(onTarget - cp.normal * 10f);

        var push = Vector3.Dot(onTarget - mySupportTowardTarget, cp.normal);
        t.position = position + cp.normal * push + cp.normal * stickOffset;
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
        if (_coll == null)
        {
            t.position = cp.point + cp.normal * stickOffset;
            return;
        }

        var position = t.position;
        var onGround = groundCol.ClosestPoint(position);
        var mySupportTowardGround = _coll.ClosestPoint(onGround - cp.normal * 10f);

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
        if (_coll == null)
        {
            t.position = cp.point + cp.normal * stickOffset;
            return;
        }

        var position = t.position;
        var onWall = wallCol.ClosestPoint(position);
        
        var mySupportTowardWall = _coll.ClosestPoint(onWall - cp.normal * 10f);
        var push = Vector3.Dot(onWall - mySupportTowardWall, cp.normal);
        position = position + cp.normal * push + cp.normal * stickOffset;
        t.position = position;
    }

    private static float NormalizeAngle(float a)
    {
        a %= 360f;
        if (a > 180f) a -= 360f;
        return a;
    }
}