using UnityEngine;

public class MovementManager : MonoBehaviour
{
    [SerializeField] private Transform canon;
    [Header("Settings")]
    [SerializeField] private float canonTopLimit = 15f;
    [SerializeField] private float canonBottomLimit = 30f;
    [SerializeField] private float moveSpeed = 5f;
    [SerializeField] private float mouseSensitivity = 2f;

    private float _playerYRotation, _canonXRotation;
    
    private Rigidbody rb;
    
    public bool MovementOn { get; set; }

    public void StartGame()
    {
        _playerYRotation = transform.rotation.eulerAngles.y;
        
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
    }

    private void Update()
    {
        HandleMovement();
        HandleMouseLook();
    }

    private void HandleMovement()
    {
        if (!MovementOn) return;

        float h = Input.GetAxisRaw("Horizontal");
        float v = Input.GetAxisRaw("Vertical");

        // No input = no sliding
        if (h == 0f && v == 0f)
        {
            var vel = rb.linearVelocity;
            rb.linearVelocity = new Vector3(0f, vel.y, 0f);
            return;
        }

        Vector3 moveDir = (transform.right * h + transform.forward * v).normalized;
        Vector3 targetVel = moveDir * moveSpeed;

        // Keep gravity (Y) but control XZ fully
        rb.linearVelocity = new Vector3( targetVel.x, rb.linearVelocity.y, targetVel.z );
    }

    private void HandleMouseLook()
    {
        if (!MovementOn)
            return;
        
        var mouseX = Input.GetAxis("Mouse X") * -1 * mouseSensitivity * 100f * Time.deltaTime;
        _playerYRotation -= mouseX;
        transform.localRotation = Quaternion.Euler(0f, _playerYRotation, 0f);
        
        var mouseY = Input.GetAxis("Mouse Y") * -1 * mouseSensitivity * 100f * Time.deltaTime;
        _canonXRotation -= mouseY;
        _canonXRotation = Mathf.Clamp(_canonXRotation, -canonTopLimit, canonBottomLimit);

        canon.localRotation = Quaternion.Euler(_canonXRotation, 0f, 0f);
    }
}