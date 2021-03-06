module LocusFocus
  module Acts #:nodoc: all
    module PolymorphicPaperclip
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # Extends the model to afford the ability to associate other records with the receiving record.
        #
        # This module needs the paperclip plugin to work
        # http://www.thoughtbot.com/projects/paperclip
        def acts_as_polymorphic_paperclip(options = {})
          write_inheritable_attribute(:acts_as_polymorphic_paperclip_options, {
            :counter_cache => options[:counter_cache],
            :attachable_field => options[:attachable_field] || :data
          })
          class_inheritable_reader :acts_as_polymorphic_paperclip_options

          has_many :attachings, :as => :attachable, :dependent => :destroy
          has_many :assets, :through => :attachings do
            def attach(asset_id)
              asset_id = extract_id(asset_id)
              asset = Asset.find(asset_id)
              @owner.assets << asset
              @owner.assets(true)
            end

            def detach(asset_id)
              asset_id = extract_id(asset_id)
              attaching = @owner.attachings.find(:first, :conditions => ['asset_id = ?', asset_id])
              raise ActiveRecord::RecordNotFound unless attaching
              attaching.destroy
            end

            protected
            def extract_id(obj)
              return obj.id unless obj.class == Fixnum || obj.class == String
              obj.to_i if obj.to_i > 0
            end
          end

          # Virtual attribute for the ActionController::UploadedStringIO
          # which consists of these attributes "content_type", "original_filename" & "original_path"
          # content_type: image/png
          # original_filename: 64x16.png
          # original_path: 64x16.png
          attr_accessor :data

          include LocusFocus::Acts::PolymorphicPaperclip::InstanceMethods
        end
      end
      module InstanceMethods
        def after_save
          super
          Asset.transaction do
            attachable_field = acts_as_polymorphic_paperclip_options[:attachable_field]
            #finder_method = "find_or_initialize_by_#{attachable_field}_file_name"
            #the_asset = Asset.send( finder_method.to_sym, self.data.original_filename)
            #the_asset.send( "#{attachable_field.to_s}=".to_sym, data )
            the_asset = Asset.find_or_initialize_by_data_file_name(self.data.original_filename)
            the_asset.data = self.data

            # Set any attributes (or other variables) in the asset model from the attributes or variables in 
            # the owning model.  Essentially a pass through from the form.
            self.instance_variables.each do |var|
              if var.include?( "@#{attachable_field}_" )
                attr_name = var.gsub( /@#{attachable_field}_/, '' )
                the_asset.send( "#{attr_name}=".to_sym, self.send( var.gsub( /@/, '' ).to_sym ) ) if the_asset.respond_to?( "#{attr_name}=".to_sym )
              end
            end

            if the_asset.save

              # This association may be saved more than once within the same request / response
              # cycle, which leads to needless DB calls. Now we'll clear out the data attribute
              # once the record is successfully saved any subsequent calls will be ignored.
              data = nil
              Attaching.find_or_create_by_asset_id_and_attachable_type_and_attachable_id(:asset_id => the_asset.id, :attachable_type => self.class.to_s, :attachable_id => self.id)
              assets(true) # implicit reloading
            end
          end unless data.nil? || data.blank?
        end
      end
    end
  end
end

