unit Reverse.Graph;

interface

uses Reverse.Domain, System.Generics.Collections;

type
  TReverseGraph = class
  private
    FByUsed: TObjectDictionary<string, TList<TDependency>>;
    FNames: TDictionary<string, string>;
    function GetConsumers(const Used: string): TList<TDependency>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Edge: TDependency);
    function Reachable(const Target: string): TArray<TDependency>;
    function Paths(const Target, ProgramName: string;
      MaxPaths: Integer = 10000): TArray<string>;
    property Consumers[const Used: string]: TList<TDependency> read GetConsumers;
  end;

implementation

uses System.SysUtils;

constructor TReverseGraph.Create;
begin
  inherited;
  FByUsed := TObjectDictionary<string, TList<TDependency>>.Create([doOwnsValues]);
  FNames := TDictionary<string, string>.Create;
end;

destructor TReverseGraph.Destroy;
begin
  FNames.Free;
  FByUsed.Free;
  inherited;
end;

function TReverseGraph.GetConsumers(const Used: string): TList<TDependency>;
begin
  if not FByUsed.TryGetValue(Key(Used), Result) then Result := nil;
end;

procedure TReverseGraph.Add(const Edge: TDependency);
var
  List: TList<TDependency>;
  UsedKey: string;
begin
  UsedKey := Key(Edge.UsedName);
  if not FByUsed.TryGetValue(UsedKey, List) then
  begin
    List := TList<TDependency>.Create;
    FByUsed.Add(UsedKey, List);
  end;
  List.Add(Edge);
  FNames.AddOrSetValue(UsedKey, Edge.UsedName);
end;

function TReverseGraph.Reachable(const Target: string): TArray<TDependency>;
var
  Queue: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  Output: TList<TDependency>;
  Current, Next: string;
  Edge: TDependency;
  Edges: TList<TDependency>;
begin
  Queue := TQueue<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Output := TList<TDependency>.Create;
  try
    Queue.Enqueue(Key(Target));
    Seen.Add(Key(Target), True);
    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      Edges := GetConsumers(Current);
      if Edges = nil then Continue;
      for Edge in Edges do
      begin
        Output.Add(Edge);
        Next := Key(Edge.Consumer);
        if not Seen.ContainsKey(Next) then
        begin
          Seen.Add(Next, True);
          Queue.Enqueue(Next);
        end;
      end;
    end;
    Result := Output.ToArray;
  finally
    Output.Free;
    Seen.Free;
    Queue.Free;
  end;
end;

function TReverseGraph.Paths(const Target, ProgramName: string;
  MaxPaths: Integer): TArray<string>;
type
  TFrame = record
    Name: string;
    NextEdge: Integer;
  end;
var
  Output: TList<string>;
  Stack: TList<string>;
  Frames: TList<TFrame>;
  Stopped: Boolean;
  Frame, ChildFrame: TFrame;
  Edges: TList<TDependency>;
  Next: string;
begin
  if MaxPaths < 1 then raise Exception.Create('MaxPaths must be positive');
  Output := TList<string>.Create;
  Stack := TList<string>.Create;
  Frames := TList<TFrame>.Create;
  try
    Stopped := False;
    Stack.Add(Key(Target));
    Frame.Name := Key(Target);
    Frame.NextEdge := 0;
    Frames.Add(Frame);
    while (Frames.Count > 0) and not Stopped do
    begin
      Frame := Frames[Frames.Count - 1];
      if SameText(Frame.Name, ProgramName) then
      begin
        Output.Add(String.Join(' -> ', Stack.ToArray) + ' [DPR]');
        Stopped := Output.Count >= MaxPaths;
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      Edges := GetConsumers(Frame.Name);
      if (Edges = nil) or (Edges.Count = 0) then
      begin
        Output.Add(String.Join(' -> ', Stack.ToArray) + ' [NO CONSUMER]');
        Stopped := Output.Count >= MaxPaths;
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      if Frame.NextEdge >= Edges.Count then
      begin
        Frames.Delete(Frames.Count - 1);
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      Next := Key(Edges[Frame.NextEdge].Consumer);
      Inc(Frame.NextEdge);
      Frames[Frames.Count - 1] := Frame;
      if Stack.Contains(Next) then
      begin
        Output.Add(String.Join(' -> ', Stack.ToArray) + ' -> ' + Next + ' [CYCLE]');
        Stopped := Output.Count >= MaxPaths;
        Continue;
      end;
      ChildFrame.Name := Next;
      ChildFrame.NextEdge := 0;
      Frames.Add(ChildFrame);
      Stack.Add(Next);
    end;
    if Stopped then Output.Add('[PATH LIST LIMITED; GRAPH RETAINS ALL REACHABLE EDGES]');
    Result := Output.ToArray;
  finally
    Frames.Free;
    Stack.Free;
    Output.Free;
  end;
end;

end.
