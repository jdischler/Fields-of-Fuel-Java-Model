require 'rspec'
require 'json'
require 'rspec/autorun'

  scriptloc = File.expand_path(File.dirname(__FILE__))
  $CLASSPATH << "#{scriptloc}/../*"
  $CLASSPATH << "#{scriptloc}/../akka/*"
  $CLASSPATH << "#{scriptloc}/../javaGame/kosomodel/target/kosomodel-0.0.1-SNAPSHOT"
  $CLASSPATH << "#{scriptloc}/../javaGame/json-simple-1.1.1.jar"

  require 'java'
  require "#{scriptloc}/../scala-library.jar"
  require "#{scriptloc}/../akka/config-1.0.0.jar"
  require "#{scriptloc}/../akka/akka-actor_2.10-2.1.1.jar"
  require "#{scriptloc}/../javaGame/kosomodel/target/kosomodel-0.0.1-SNAPSHOT.jar"
  require "#{scriptloc}/../javaGame/json-simple-1.1.1.jar"

  # require 'akka-project-in-java/src/main/java/akka/test/AkkaProjectInJava'
  # require 'JavaActor.jar'

  java_import 'java.io.Serializable'
  java_import 'akka.actor.UntypedActor'
  java_import 'akka.actor.ActorRef'
  java_import 'akka.actor.ActorSystem'
  java_import 'akka.actor.Props'
  java_import 'scala.concurrent.Future'
  java_import 'scala.concurrent.Future'
  java_import 'scala.concurrent.Await'
  java_import 'akka.util.Timeout'
  java_import 'scala.concurrent.duration.Duration'
  java_import 'akka.pattern.Patterns'
  java_import 'java.util.concurrent.TimeUnit'

  java_import "com.biofuels.fof.kosomodel.Handler"
  java_import "com.biofuels.fof.kosomodel.EventMessage"
  java_import "com.biofuels.fof.kosomodel.ActorSystemHelper"

  require 'test_messages'
  # require "#{scriptloc}/../kosomodel/target/kosomodel-0.0.1-SNAPSHOT.jar"

# require 'java_loader_rspec'
  # java_import 'AkkaProjectInJava'
  # java_import 'AkkaProjectInJava.Counter'

include TestMessages

class BaseActor < UntypedActor
    def self.create(*args)
      self.new(*args)
    end

    def self.build(*args)
      return Akka::UntypedActor.actorOf(self)  if args.empty?
      Akka::UntypedActor.actorOf { self.new *args }
    end

    def self.spawn(*args)
      build(*args).start
    end
  end

class ModelWrapper < BaseActor
  def onReceive(msg)
    if msg.is_a? String
      # puts "got a string: #{msg}"
      if msg == "hello?"
        getSender().tell("hihi")
      end
    elsif msg.is_a? TestMessage
      @replyaddr = getSender()
      @replies = []
      @expected_replies = msg.test_message.expected_replies
      # @timeout = Timeout.new(Duration.create(15, TimeUnit::SECONDS));
      msg.handler.tell(msg.event)
    elsif msg.is_a? EventMessage

      if @replies.count < @expected_replies
        @replies << msg.message
      elsif @replies.count > @expected_replies
        puts "unexpected number of replies"
        raise "unexpected number of replies" unless @expected_replies == -1
      end

      if @replies.count == @expected_replies
        if @expected_replies == 1
          ## making this/these here/when they come in a proper message might help concurrency issues?
          returnMsg = @replies[0]
        else
          returnMsg = @replies
        end
        if !returnMsg
          puts "return message nil :("
        end
        @replyaddr.tell(returnMsg)
      end

    elsif msg.test_message
      @replyaddr = getSender()
      @replies = []
      @expected_replies = msg.test_message.expected_replies
      # puts "testing #{msg.test_message.event.message}"
      # puts "expecting #{@expected_replies} replies"
      msg.test_message.handler.tell(msg.test_message.event)
    end
  end
end





########################################################################################################################
########################################################################################################################
#
#
#
#                                       TESTS
#
#
#
#
########################################################################################################################
########################################################################################################################




describe ModelWrapper do

  def askActor(message_type, expect_count=1, options=@template)
    future = Patterns.ask(@listener, message_type.new(@handler, options, expect_count), @timeout)
    if expect_count != 0
      result = Await.result(future, @timeout.duration())
      if result.is_a? Array
        result.map! { |r| JSON.parse(r) }
      else
        result = JSON.parse(result)
      end
    else
      result = "No result asked for!"
    end
    result
  end

  def reset_template!
    @template = {
      "roomName" => "noNameRoom",
      "clientID" => "0",
      "password" => "",
      "deviseName" => "fake@fake.com",
      "userName" => "Joe Farmer",
      "roomID" => "noNameRoom"
    }
  end

  before(:each) do
    @system = ActorSystem.create("BiofuelsTest")
    @listener = @system.actorOf(Props.new(ModelWrapper), "listener")
    @timeout = Timeout.new(Duration.create(3, TimeUnit::SECONDS));
    jside = ActorSystemHelper.new
    @handler = jside.makenew(@system, Handler, "handler")  # = system.actorOf(pro, "counter")
    @handler.tell(@listener)
    @template = {
      "roomName" => "noNameRoom",
      "clientID" => "0",
      "password" => "",
      "deviseName" => "fake@fake.com",
      "userName" => "Joe Farmer",
      "roomID" => "noNameRoom"
    }
    askActor(CreateRoomMessage)["result"].should == true

  end

  after(:each) do
    @system.shutdown
    @system.await_termination
  end

  it "creates and talk to actor" do
    future = Patterns.ask(@listener, "hello?", @timeout);
    result = Await.result(future, @timeout.duration());
    result.should == "hihi"
    # should be "hello"
  end

  it "asks if a room is open" do
    @template["roomName"] = "new Room"
    askActor(ValidateRoomMessage)["result"].should == true
  end

  it "creates room" do
    @template["roomName"] = "new Room"
    askActor(CreateRoomMessage)["result"].should == true
  end

  it "can't create room twice" do
    askActor(CreateRoomMessage)["result"].should == false
  end

  it "sees existing rooms as invalid for creation" do
    askActor(ValidateRoomMessage)["result"].should == false
  end

  it "creates a passworded room" do
    @template["password"]="apassword"
    @template["roomName"] = "new Room"
    askActor(CreateRoomMessage)["result"].should == true
  end

  it "is invalid for user on empty room" do
    @template["roomName"] = "new Room"
    askActor(JoinGameMessage)["result"].should == false
  end

  it "is valid for user on extant room" do
    result = askActor(ValidateUserMessage)
    result["roomResult"].should == true
    result["userNameResult"].should == true
  end

  it "joins created games" do
    askActor(JoinGameMessage)["result"].should == true
  end

  it "rejoins game in progress if has same devise name" do
    askActor(JoinGameMessage)["result"].should == true
    askActor(JoinGameMessage)["result"].should == true
  end

  it "can't rejoin game in progress if has different devise name" do
    askActor(JoinGameMessage)["result"].should == true
    reset_template!
    @template["deviseName"] = "someone@else.com"
    res = askActor(JoinGameMessage)
    unless res["result"]
      # puts "\n no result field for rejoin test, probably concurrency problem"
      "#{res}"
    end
    res["result"].should == false
  end

  it "joins password games if password is known" do
    @template["password"]="apassword"
    @template["roomName"] = "new Room"
    askActor(CreateRoomMessage)["result"].should == true
    askActor(JoinGameMessage)["result"].should == true
  end

  it "can't join password protected games without the right password" do
    @template["password"] = "apassword"
    @template["roomName"] = "new Room"
    askActor(CreateRoomMessage)["result"].should == true

    @template["password"]="wrongpass"
    askActor(JoinGameMessage)["result"].should == false
  end

  it "sends out both confirmation and room info on a successful join" do

    joinReply = askActor(JoinGameMessage, 2)
    joinReply[0]["result"].should == true
    joinReply[1]["event"].should == "farmerList"
    joinReply[1]["Farmers"][0]["name"].should == @template["userName"]
  end

  it "is assigned 2 fields with corn on loading" do
    askActor(JoinGameMessage, 2)

    # fields = askActor(LoadFieldsMessage)["fields"]

    askActor(LoadFieldsMessage)["fields"][0]["crop"].should == "CORN"
  end

  it "can plant switchgrass on first field" do
    askActor(JoinGameMessage, 2)
    @template["crop"] = "grass"
    askActor(PlantMessage, 0)
    fields = askActor(LoadFieldsMessage)["fields"]
    fields[0]["crop"].should == "GRASS"
  end

  it "can use fertilizer on fields" do
    ## eventually should have check for management being on
    askActor(JoinGameMessage)
    @template["field"] = 0
    @template["technique"] = "fertilizer"
    @template["value"] = true
    @template["event"] = "setFieldManagement"
    askActor(GenericMessage, 0)

    reset_template!

    fields = askActor(LoadFieldsMessage)["fields"]
    # unless fields[0]
    #   puts "missing fields #{fields}"
    # end
    fields[0]["fertilizer"].should == true
  end

  it "can use pesticide on fields" do
    askActor(JoinGameMessage)
    @template["field"] = 0
    @template["technique"] = "pesticide"
    @template["value"] = true
    @template["event"] = "setFieldManagement"
    askActor(GenericMessage, 0)

    reset_template!

    fields = askActor(LoadFieldsMessage)["fields"]
    # unless fields[0]
    #   puts "missing fields #{fields}"
    # end
    fields[0]["pesticide"].should == true
  end

  it "can use tillage on fields" do
    askActor(JoinGameMessage)
    @template["field"] = 0
    @template["technique"] = "tillage"
    @template["value"] = true
    @template["event"] = "setFieldManagement"
    askActor(GenericMessage, 0)

    reset_template!

    fields = askActor(LoadFieldsMessage)["fields"]
    # unless fields[0]
    #   puts "missing fields #{fields}"
    # end
    fields[0]["tillage"].should == true
  end

  it "can get game year, current stage, and enabled stages" do
    @template["event"] = "getGameInfo"
    reply = askActor(GenericMessage, 1)
    reply["year"].should >= 0
    reply["stage"].should >= 0
    reply["enabledStages"].should_not be nil
  end

  it "can advance stages" do
    @template["event"] = "getGameInfo"
    reply = askActor(GenericMessage, 1)
    reply["stage"].should == 0

    reset_template!

    # puts "got game info 1"

    @template["event"] = "advanceStage"
    reply = askActor(GenericMessage, 1)
    reply["event"].should == "advanceStage"
    reply["stageNumber"].should > 0

    # puts "advanced stage"
    reset_template!


    @template["event"] = "getGameInfo"
    reply = askActor(GenericMessage, 1)
    reply["stage"].should > 0
  end

  it "does not crash when a change settings message is sent before any farms exist" do
    @template["event"] = "changeSettings"
    @template["fieldCount"] = 2
    # works for now, but should write a test
  end

  it "updates game settings when a change settings message is sent" do
    @template["event"] = "changeSettings"
    @template["fieldCount"] = 2
    @template["contractsOn"] = false
    @template["mgmtOptsOn"] = false
    askActor(GenericMessage, 0)

    reset_template!
    @template["event"] = "advanceStage"

    askActor(GenericMessage, 1)["stageNumber"].should == 1 #1
    askActor(GenericMessage, 1) #2
    askActor(GenericMessage, 1)["stageNumber"].should == 0 #0
  end

  it "loops to first stage after round is over" do
    @template["event"] = "changeSettings"
    @template["fieldCount"] = 2
    @template["contractsOn"] = true
    @template["mgmtOptsOn"] = true
    askActor(GenericMessage, 0)

    reset_template!
    @template["event"] = "getGameInfo"
    reply = askActor(GenericMessage, 1)
    reply["stage"].should == 0
    reply["enabledStages"].should_not be nil

    reset_template!
    @template["event"] = "advanceStage"
    askActor(GenericMessage, 1)["stageNumber"].should == 1

    reset_template!
    @template["event"] = "advanceStage"
    askActor(GenericMessage, 1)["stageNumber"].should == 2

    reset_template!
    @template["event"] = "advanceStage"
    askActor(GenericMessage, 1)["stageNumber"].should == 3

    reset_template!
    @template["event"] = "advanceStage"
    askActor(GenericMessage, 1)["stageNumber"].should == 4

    reset_template!
    @template["event"] = "advanceStage"
    askActor(GenericMessage, 1)["stageNumber"].should == 0

    reset_template!
    @template["event"] = "advanceStage"
    askActor(GenericMessage, 1)["stageNumber"].should == 1
  end
end