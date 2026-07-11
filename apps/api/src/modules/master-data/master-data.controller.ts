import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { MasterDataService } from './master-data.service';

@ApiTags('master-data')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller('master-data')
export class MasterDataController {
  constructor(private svc: MasterDataService) {}

  @Get('templates') getTemplates() { return this.svc.getTemplates(); }
  @Get('sterilizers') getSterilizers() { return this.svc.getSterilizers(); }
}
