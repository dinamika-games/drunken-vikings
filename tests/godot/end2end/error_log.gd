extends Logger
## Catch every error and warning of the engine and of the scripts while the
## end-to-end test plays (see [method OS.add_logger]), so that the test fails
## on any of them, even on those which the game survives (e.g., a call on a
## freed node, a texture which does not load).
##
## The engine may log from any thread, hence the mutex.
##
## Not a test itself (its name does not start with test_).

## The warnings which are expected and harmless.
const EXPECTED := ["The camera is switched off"]

var _mutex := Mutex.new()
var _errors: Array[String] = []
var _warnings: Array[String] = []


func _log_error(
    function: String,
    file: String,
    line: int,
    code: String,
    rationale: String,
    _editor_notify: bool,
    error_type: int,
    _script_backtraces: Array[ScriptBacktrace]
) -> void:
    var what := rationale if rationale != "" else code
    for expected in EXPECTED:
        if expected in what:
            return
    var message := "%s (%s:%d, %s)" % [what, file, line, function]
    _mutex.lock()
    if error_type == ERROR_TYPE_WARNING:
        _warnings.append(message)
    else:
        _errors.append(message)
    _mutex.unlock()


## The errors logged so far (scripts, engine, shaders).
func errors() -> Array[String]:
    _mutex.lock()
    var result := _errors.duplicate()
    _mutex.unlock()
    return result


## The warnings logged so far.
func warnings() -> Array[String]:
    _mutex.lock()
    var result := _warnings.duplicate()
    _mutex.unlock()
    return result
