using UnityEngine;

public class MovementManager : MonoBehaviour
{
    [Header("Settings")]
    [SerializeField] private float moveSpeed = 5f;
    [SerializeField] private float mouseSensitivity = 2f;

    private float _playerYRotation;

    private void Start()
    {
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
        var h = Input.GetAxis("Horizontal");
        var v = Input.GetAxis("Vertical");

        var t = transform;
        var move = (t.right * h + t.forward * v) * moveSpeed;
        t.position += move * Time.deltaTime;
    }

    private void HandleMouseLook()
    {
        var mouseX = Input.GetAxis("Mouse X") * -1 * mouseSensitivity * 100f * Time.deltaTime;

        _playerYRotation -= mouseX;

        transform.localRotation = Quaternion.Euler(0f, _playerYRotation, 0f);
    }
}