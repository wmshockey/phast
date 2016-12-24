class Schedule < ActiveRecord::Base
    belongs_to :simulation
    has_many :activities, dependent: :destroy
    validates :name, :presence => true
    validates :description, allow_blank: true, length: { maximum: 512 }
    validates :start_date, :presence => true
    validates :period, :presence => true, numericality: {:greather_than_or_equal_to => 0, :less_than => 366}
    validates :pipeline_name, allow_blank: true, length: { maximum: 512 }
    validates :sched_type, :presence => true, inclusion: { in: %w(PRIOR PRELIMINARY SIMULATED), message: "%{value} is not a valid schedule type" }


    def initialize_batch_sequence(prior_activities, statar)      
#     Go through previous schedule to identify injections and receipts to get list of batches
      prior_activities = prior_activities.sort_by {|a| a.start_time}
      batches = Array.new
      batch_list = prior_activities.map {|p| p.batch_id}.uniq 
      batch_list.each do |b|
        batch_activities = prior_activities.select {|p| p.batch_id == b}
        batch_temp = batch_activities[0].batch_id.partition("-")
        commodity_id = batch_temp[0]
        batch_number = batch_temp[2].partition(" ")[0]
        batch_volume = batch_activities[0].volume
        batch_shipper = batch_activities[0].shipper 
        batch_nomination = batch_activities[0].nomination_name
        start_location = ""
        end_location = ""    
        batch_activities.each do |ba|
          if ba.activity_type == "INJECTION" then
            start_location = ba.station
          elsif ba.activity_type == "RECEIPT" then
            start_location = ba.station
          elsif ba.activity_type == "LANDING" then
            end_location = ba.station
          elsif ba.activity_type == "DELIVERY" then
            end_location = ba.station
          end
        end
        batches << Batchrec.new(batch_number, commodity_id, batch_volume, start_location, end_location, batch_shipper, batch_nomination)
#       Assign the batch id's
        batches.each_with_index do |b, bix|
          b.batch_id = b.commodity_id + "-" + b.batch_number.to_s.rjust(5, "0")
        end
      end
#     Create the two-dimensional batch sequence array
      max_batches = batches.count
      bs = Array.new(statar.count-1){Array.new(max_batches)}
      batches.each_with_index do |b, btix|
        start_loc = b.start_location
        station_rec = statar.detect {|s| s.name == start_loc}
        start_kmp = station_rec.kmp
        end_loc = b.end_location
        station_rec = statar.detect {|s| s.name == end_loc}
        end_kmp = station_rec.kmp
        statar[0...-1].each_with_index do |s, stix|
          stat = s.name
          kmp = s.kmp
          if start_kmp <= kmp and end_kmp > kmp then
            bs[stix][btix] = batches[btix].dup
          else
            bs[stix][btix] = batches[btix].dup
            bs[stix][btix].volume = 0.0
          end
          s.sequence_volume = s.sequence_volume + bs[stix][btix].volume
        end
      end
      return bs
    end     

    def finalize_batch_sequence(max_batchsize, btsqar, shipments, statar)
#     Break up shipments into batches
      logger.info "max_batchsize=#{max_batchsize}"
      batches = Array.new
      number_of_shipments = shipments.count
      total_volume_of_shipments = shipments.sum("volume")
      total_number_of_batches = total_volume_of_shipments / max_batchsize
      shipments.each_with_index do |s, ix|
        number_of_batches_in_shipment = s.volume / max_batchsize
        spacing_of_batches = (total_number_of_batches / number_of_batches_in_shipment).round
        vol = s.volume
        batch_number_within_shipment = 0
        while vol > max_batchsize
          batch_number = (ix+1) + batch_number_within_shipment * spacing_of_batches
          batches << Batchrec.new(batch_number, s.commodity_id, max_batchsize, s.start_location, s.end_location, s.shipper, ix+1)
          vol = vol - max_batchsize
          batch_number_within_shipment = batch_number_within_shipment + 1
        end
        if vol > 0.0 then
          batch_number = (ix+1) + batch_number_within_shipment * spacing_of_batches
          batches << Batchrec.new(batch_number, s.commodity_id, vol, s.start_location, s.end_location, s.shipper, ix+1)
        end
      end
#     Re-order the batches by batch_number to spread shipment batches out over the month for best ratability and assign batch id's for each.
#     Give newly nominated batches a batch number starting at 10000 to distinguish them from old batches previously in the line from prior schedule.
      batches.sort! { |a, b| a.batch_number <=> b.batch_number }
      batches.each_with_index do |b, bix|
        b.batch_number = 10000 + bix + 1
        b.batch_id = b.commodity_id + "-" + b.batch_number.to_s.rjust(5, "0")
      end
#     Create the two-dimensional batch sequence array
      max_batches = batches.count
      bs = Array.new(statar.count-1){Array.new(max_batches)}
      batches.each_with_index do |b, btix|
        start_loc = b.start_location
        station_rec = statar.detect {|s| s.name == start_loc}
        start_kmp = station_rec.kmp
        end_loc = b.end_location
        station_rec = statar.detect {|s| s.name == end_loc}
        end_kmp = station_rec.kmp
        statar[0...-1].each_with_index do |s, stix|
          stat = s.name
          kmp = s.kmp
          if start_kmp <= kmp and end_kmp > kmp then
            bs[stix][btix] = batches[btix].dup
          else
            bs[stix][btix] = batches[btix].dup
            bs[stix][btix].volume = 0.0
          end
          s.sequence_volume = s.sequence_volume + bs[stix][btix].volume
        end
      end
#     Now tack the new batches from the nomination shipments onto the end of the existing batch sequence array btsqar
      number_of_prior_batches = btsqar[0].length
      final_bs = Array.new(statar.count-1){Array.new(max_batches + number_of_prior_batches)}
      statar[0...-1].each_with_index do |s, stix|
        final_bs[stix] = btsqar[stix] + bs[stix]
      end
      return final_bs
    end




end