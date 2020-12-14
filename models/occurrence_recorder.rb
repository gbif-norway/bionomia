class OccurrenceRecorder < ActiveRecord::Base

   self.primary_key = [:agent_id, :occurrence_id]

   belongs_to :occurrence
   belongs_to :agent

   validates :occurrence_id, presence: true
   validates :agent_id, presence: true
end
