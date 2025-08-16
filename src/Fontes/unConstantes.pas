unit unConstantes;

interface

resourcestring
    sPortInUse = '- Error: Port %s already in use';
    sPortSet = '- Port set to %s';
    sServerRunning = '- The Server is already running';
    sStartingServer = '- Starting HTTP Server on port %d';
    sStoppingServer = '- Stopping Server';
    sServerStopped = '- Server Stopped';
    sServerNotRunning = '- The Server is not running';
    sInvalidCommand = '- Error: Invalid Command';
    sActive = '- Active: ';
    sPort = '- Port: ';
    sSessionID = '- Session ID CookieName: ';
    sCommands = 'Enter a Command: ' + slineBreak +
      '   - "start" to start the server'+ slineBreak +
      '   - "stop" to stop the server'+ slineBreak +
      '   - "help" to show commands'+ slineBreak +
      '   - "exit" to close the application';

const
    cArrow = '->';
    cCommandStart = 'start';
    cCommandStop = 'stop';
    cCommandHelp = 'help';
    cCommandExit = 'exit';

implementation

end.
