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
        if (!MovementOn)
            return;
        
        var h = Input.GetAxis("Horizontal");
        var v = Input.GetAxis("Vertical");
        
        if (h == 0f && v == 0f)
            return;

        var t = transform;
        var move = (t.right * h + t.forward * v) * moveSpeed;
        t.position += move * Time.deltaTime;
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